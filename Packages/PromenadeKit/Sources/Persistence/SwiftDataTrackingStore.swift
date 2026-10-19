import Domain
import Foundation
import SwiftData

// Conforms to `ModelActor` manually instead of using `@ModelActor`: the macro adds a public
// `init(modelContainer:)` that would bypass the context setup below.
public actor SwiftDataTrackingStore: TrackingStore, ModelActor {
  public nonisolated let modelContainer: ModelContainer
  public nonisolated let modelExecutor: any ModelExecutor
  private let configuration: TrackingConfiguration
  private let saveOperation: @Sendable (ModelContext) throws -> Void
  private var cursor: SessionCursor?
  /// Points inserted since the last successful save, kept as values so they can be replayed
  /// after a rollback (retaining @Model instances would retain invalidated objects).
  private var pendingPoints: [PendingPoint] = []
  /// Pending point count at which `append` attempts the next save.
  private var nextPointSaveThreshold: Int
  private var needsReplay = false

  public init(container: ModelContainer, configuration: TrackingConfiguration = .default) {
    self.init(container: container, configuration: configuration, save: { try $0.save() })
  }

  /// An internal save boundary lets tests exercise failures without replacing SwiftData itself.
  init(
    container: ModelContainer, configuration: TrackingConfiguration = .default,
    save: @escaping @Sendable (ModelContext) throws -> Void
  ) {
    precondition(configuration.saveBatchSize > 0)
    let context = ModelContext(container)
    // Every durable write is explicit: autosave could persist half a state transition.
    context.autosaveEnabled = false
    self.modelContainer = container
    self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    self.configuration = configuration
    self.saveOperation = save
    self.nextPointSaveThreshold = configuration.saveBatchSize
  }

  public func createSession(id: UUID, startDate: Date, timeZone: TimeZone) throws {
    try prepare()
    guard try fetchSession(id: id) == nil else { throw PersistenceError.duplicateSession(id) }
    let session = WalkingSession(
      id: id, startDate: startDate, stateRaw: SessionState.recording.rawValue,
      timeZoneIdentifier: timeZone.identifier)
    modelContext.insert(session)
    addSegment(to: session, index: 0, at: startDate)
    cursor = nil
    try commitTransition()
  }

  public func append(_ point: TrackPoint, sessionID: UUID) throws {
    try prepare()
    let (session, current) = try locate(sessionID)
    try requireState(session, .recording)
    let segment = try openSegment(for: current)
    guard point.timestamp >= segment.startDate,
      current.lastPointDate.map({ point.timestamp > $0 }) ?? true
    else { throw PersistenceError.invalidPointTimestamp }
    insert(point, into: segment)
    pendingPoints.append(PendingPoint(segmentID: segment.id, point: point))
    cursor?.lastPointDate = point.timestamp
    cursor?.lastActivity = max(current.lastActivity, point.timestamp)
    if pendingPoints.count >= nextPointSaveThreshold { try commitPoints() }
  }

  public func pause(sessionID: UUID, at date: Date) throws {
    try prepare()
    let (session, current) = try locate(sessionID)
    try requireState(session, .recording)
    let segment = try openSegment(for: current)
    try validate(date, after: current.lastActivity)
    close(segment, at: date, reason: .paused)
    session.stateRaw = SessionState.paused.rawValue
    cursor = nil
    // Segment and session state must become durable together, including any pending points.
    try commitTransition()
  }

  public func resume(sessionID: UUID, at date: Date) throws {
    try prepare()
    let (session, current) = try locate(sessionID)
    try requireState(session, .paused)
    try beginSegment(session: session, cursor: current, at: date)
    session.stateRaw = SessionState.recording.rawValue
    try commitTransition()
  }

  public func splitSegment(
    sessionID: UUID, closingAt: Date, reason: SegmentEndReason, nextStart: Date
  ) throws {
    try prepare()
    guard reason == .signalGap || reason == .interrupted else {
      throw PersistenceError.invalidSplitReason
    }
    let (session, current) = try locate(sessionID)
    try requireState(session, .recording)
    let segment = try openSegment(for: current)
    try validate(closingAt, after: current.lastActivity)
    try validate(nextStart, after: closingAt)
    close(segment, at: closingAt, reason: reason)
    addSegment(to: session, index: current.nextIndex, at: nextStart)
    cursor = nil
    try commitTransition()
  }

  public func interruptSegment(sessionID: UUID, at date: Date) throws {
    try prepare()
    let (session, current) = try locate(sessionID)
    try requireState(session, .recording)
    let segment = try openSegment(for: current)
    try validate(date, after: current.lastActivity)
    close(segment, at: date, reason: .interrupted)
    cursor = nil
    try commitTransition()
  }

  public func openSegment(sessionID: UUID, at date: Date) throws {
    try prepare()
    let (session, current) = try locate(sessionID)
    try requireState(session, .recording)
    try beginSegment(session: session, cursor: current, at: date)
    try commitTransition()
  }

  public func finish(sessionID: UUID, at date: Date) throws {
    try prepare()
    let (session, current) = try locate(sessionID)
    guard session.stateRaw != SessionState.finished.rawValue else {
      throw PersistenceError.invalidState
    }
    try validate(date, after: current.lastActivity)
    // Mapping can throw. Complete all fallible validation before changing managed models.
    var record = try session.record()
    record.endDate = date
    record.state = .finished
    let metrics = SessionMetricsCalculator.metrics(
      for: record, filter: RouteFilter(configuration: configuration.route), asOf: date)
    if let id = current.openSegmentID {
      guard let segment = modelContext.model(for: id) as? Segment else {
        throw PersistenceError.invalidStructure
      }
      close(segment, at: date, reason: .finished)
    }
    session.endDate = date
    session.stateRaw = SessionState.finished.rawValue
    session.distance = metrics.distance
    session.walkingDuration = metrics.timing.walking
    session.pauseDuration = metrics.timing.pause
    session.interruptionDuration = metrics.timing.interruption
    session.steps = metrics.steps
    session.derivedDataVersion = DerivedDataVersion.current
    cursor = nil
    try commitTransition()
  }

  public func flush() throws {
    try prepare()
    try commitPoints()
  }

  public func loadSession(id: UUID) throws -> SessionRecord? {
    try prepare()
    return try fetchSession(id: id)?.record()
  }

  private func fetchSession(id: UUID) throws -> WalkingSession? {
    var descriptor = FetchDescriptor<WalkingSession>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  private func locate(_ id: UUID) throws -> (WalkingSession, SessionCursor) {
    if let cursor, cursor.sessionID == id,
      let session = modelContext.model(for: cursor.modelID) as? WalkingSession
    {
      return (session, cursor)
    }
    guard let session = try fetchSession(id: id) else { throw PersistenceError.sessionNotFound(id) }
    guard SessionState(rawValue: session.stateRaw) != nil else {
      throw PersistenceError.invalidStoredValue(field: "stateRaw", value: session.stateRaw)
    }
    let segments = session.segments.sorted { $0.index < $1.index }
    let open = segments.filter { $0.endDate == nil }
    guard open.count <= 1, open.first == nil || open.first === segments.last,
      Set(segments.map(\.index)).count == segments.count
    else { throw PersistenceError.invalidStructure }
    let last = segments.last
    let lastPoint = last?.points.map(\.timestamp).max()
    // Must match `SessionRecord.lastActivityDate`: recovery dates computed in Domain are
    // validated against this value.
    let activity = SessionRecord.lastActivityDate(
      startDate: session.startDate, lastSegmentStart: last?.startDate,
      lastSegmentEnd: last?.endDate, lastPointDate: lastPoint)
    let current = SessionCursor(
      sessionID: id, modelID: session.persistentModelID,
      openSegmentID: open.first?.persistentModelID, nextIndex: (last?.index ?? -1) + 1,
      lastActivity: activity, lastPointDate: lastPoint)
    cursor = current
    return (session, current)
  }

  private func requireState(_ session: WalkingSession, _ state: SessionState) throws {
    guard session.stateRaw == state.rawValue else { throw PersistenceError.invalidState }
  }

  private func openSegment(for cursor: SessionCursor) throws -> Segment {
    guard let id = cursor.openSegmentID,
      let segment = modelContext.model(for: id) as? Segment
    else { throw PersistenceError.noOpenSegment }
    return segment
  }

  private func validate(_ date: Date, after lowerBound: Date) throws {
    guard date >= lowerBound else { throw PersistenceError.invalidDate }
  }

  private func beginSegment(session: WalkingSession, cursor: SessionCursor, at date: Date) throws {
    guard cursor.openSegmentID == nil else { throw PersistenceError.segmentAlreadyOpen }
    try validate(date, after: cursor.lastActivity)
    addSegment(to: session, index: cursor.nextIndex, at: date)
    self.cursor = nil
  }

  private func addSegment(to session: WalkingSession, index: Int, at date: Date) {
    let segment = Segment(index: index, startDate: date)
    modelContext.insert(segment)
    session.segments.append(segment)
  }

  private func close(_ segment: Segment, at date: Date, reason: SegmentEndReason) {
    segment.endDate = date
    segment.endReasonRaw = reason.rawValue
  }

  private func insert(_ point: TrackPoint, into segment: Segment) {
    let model = LocationPoint(point: point)
    modelContext.insert(model)
    segment.points.append(model)
  }

  /// Saves a state transition together with any pending points.
  private func commitTransition() throws {
    do {
      try save()
    } catch {
      // Roll back the entire failed transition. Replay only raw points on the next operation;
      // otherwise a later flush could silently commit a pause/resume that the caller saw fail.
      modelContext.rollback()
      cursor = nil
      needsReplay = !pendingPoints.isEmpty
      throw error
    }
  }

  /// Saves pending points only.
  private func commitPoints() throws {
    do {
      try save()
    } catch {
      // Nothing but points is unsaved here, so keep them in the context instead of rolling back
      // and replaying; repeated failures (e.g. a full disk) would otherwise re-insert every
      // pending point on each append. Retry after another batch instead of on every append.
      nextPointSaveThreshold = pendingPoints.count + configuration.saveBatchSize
      throw error
    }
  }

  private func save() throws {
    try saveOperation(modelContext)
    pendingPoints.removeAll(keepingCapacity: true)
    nextPointSaveThreshold = configuration.saveBatchSize
  }

  private func prepare() throws {
    guard needsReplay else { return }
    var segments: [UUID: Segment] = [:]
    // Resolve every destination before inserting anything, so a failed fetch cannot half-replay.
    for pending in pendingPoints where segments[pending.segmentID] == nil {
      let id = pending.segmentID
      var descriptor = FetchDescriptor<Segment>(predicate: #Predicate { $0.id == id })
      descriptor.fetchLimit = 1
      guard let segment = try modelContext.fetch(descriptor).first else {
        throw PersistenceError.invalidStructure
      }
      segments[id] = segment
    }
    for pending in pendingPoints {
      if let segment = segments[pending.segmentID] { insert(pending.point, into: segment) }
    }
    needsReplay = false
  }
}

private struct SessionCursor {
  let sessionID: UUID
  let modelID: PersistentIdentifier
  let openSegmentID: PersistentIdentifier?
  let nextIndex: Int
  var lastActivity: Date
  var lastPointDate: Date?
}

private struct PendingPoint {
  let segmentID: UUID
  let point: TrackPoint
}
