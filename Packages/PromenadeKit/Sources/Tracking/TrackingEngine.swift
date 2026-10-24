import Domain
import Foundation
import Observation
import Persistence
import Sensors
import os

/// Recording state machine. Location event handling lives in `TrackingEngine+Events.swift` and
/// launch recovery in `TrackingEngine+Recovery.swift`.
@MainActor
@Observable
public final class TrackingEngine {
  public internal(set) var phase: TrackingPhase = .idle
  public internal(set) var liveSession: LiveSession?
  public internal(set) var pendingTransition: PendingTransition?
  public internal(set) var startFailure: TrackingFailure?
  public internal(set) var operationFailure: TrackingFailure?
  public internal(set) var notice: TrackingNotice?
  public internal(set) var lastFinishedSessionID: UUID?
  public internal(set) var isBusy = false

  @ObservationIgnored let store: any TrackingStore
  @ObservationIgnored let provider: any LocationProvider
  @ObservationIgnored let locationSession: any LocationSession
  @ObservationIgnored let dates: any DateProvider
  @ObservationIgnored let configuration: TrackingConfiguration
  @ObservationIgnored let timeZone: @MainActor () -> TimeZone
  @ObservationIgnored let sleep: @Sendable (TimeInterval) async throws -> Void
  @ObservationIgnored let queue = TrackingOperationQueue()
  @ObservationIgnored var updatesTask: Task<Void, Never>?
  @ObservationIgnored var subscriptionID: UUID?
  @ObservationIgnored var wasStationary = false
  @ObservationIgnored var recoveryScheduled = false
  /// Whether the current `.persistence` failure came from saving points rather than a transition,
  /// so a later successful point save can clear it.
  @ObservationIgnored var pointSaveFailed = false

  /// Use the same configuration as the store so live routes and finished metrics agree.
  public init(
    store: any TrackingStore, provider: any LocationProvider,
    locationSession: any LocationSession,
    dates: any DateProvider = SystemDateProvider(),
    configuration: TrackingConfiguration = .default,
    timeZone: @escaping @MainActor () -> TimeZone = { .current },
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
      try await Task.sleep(for: .seconds($0))
    }
  ) {
    self.store = store
    self.provider = provider
    self.locationSession = locationSession
    self.dates = dates
    self.configuration = configuration
    self.timeZone = timeZone
    self.sleep = sleep
  }

  public func start() async {
    // Reject taps during launch preparation rather than replaying them after recovery completes.
    guard !recoveryScheduled else { return }
    await queue.run { [self] in
      guard phase == .idle, !recoveryScheduled else { return }
      isBusy = true
      defer { isBusy = false }
      startFailure = nil
      operationFailure = nil
      do {
        guard try await activate() else { return }
        let start = dates.now()
        let id = UUID()
        let recordingTimeZone = timeZone()
        try await store.createSession(id: id, startDate: start, timeZone: recordingTimeZone)
        liveSession = makeLive(
          SessionRecord(
            id: id, startDate: start, state: .recording,
            timeZoneIdentifier: recordingTimeZone.identifier,
            segments: [SegmentRecord(index: 0, startDate: start)]))
        lastFinishedSessionID = nil
        phase = .recording(.searching)
        wasStationary = false
        startUpdates()
      } catch is CancellationError {
        locationSession.deactivate()
      } catch {
        startFailure = .persistence
        log(error, logger: persistenceLogger)
        locationSession.deactivate()
      }
    }
  }

  /// Returns whether the request was accepted. Show the confirmation dialog only when it was;
  /// otherwise confirming would silently do nothing.
  @discardableResult
  public func requestPause(at date: Date) -> Bool { request(.pause, at: date) }

  /// Returns whether the request was accepted. See `requestPause(at:)`.
  @discardableResult
  public func requestFinish(at date: Date) -> Bool { request(.finish, at: date) }

  private func request(_ kind: PendingTransition.Kind, at date: Date) -> Bool {
    guard !isBusy, !recoveryScheduled, pendingTransition == nil,
      let liveSession, date >= liveSession.lastActivity,
      date.timeIntervalSinceReferenceDate.isFinite
    else { return false }
    switch phase {
    case .recording: break
    case .paused where kind == .finish: break
    default: return false
    }
    // Set the cutoff before returning to the UI, including while an append is suspended.
    pendingTransition = PendingTransition(kind: kind, date: date)
    return true
  }

  public func confirmPendingTransition() async {
    let id = pendingTransition?.id
    await queue.run { [self] in
      guard let pending = pendingTransition, pending.id == id, let liveSession else { return }
      isBusy = true
      defer { isBusy = false }
      do {
        switch pending.kind {
        case .pause:
          try await store.pause(sessionID: liveSession.id, at: pending.date, steps: nil)
          liveSession.pause(at: pending.date)
          phase = .paused
          stopUpdates()
        case .finish:
          try await finish(at: pending.date)
        }
        pendingTransition = nil
        clearOperationFailure()
      } catch {
        // Keep the cutoff and buffered events so the same transition can be retried or cancelled.
        report(error)
      }
    }
  }

  public func cancelPendingTransition() {
    let id = pendingTransition?.id
    queue.submit { [self] in
      guard let pending = pendingTransition, pending.id == id else { return }
      pendingTransition = nil
      for event in pending.events { await process(event) }
    }
  }

  public func resume(at date: Date) async {
    await queue.run { [self] in
      guard phase == .paused, pendingTransition == nil, let liveSession,
        date >= liveSession.lastActivity, date.timeIntervalSinceReferenceDate.isFinite
      else { return }
      isBusy = true
      defer { isBusy = false }
      do {
        guard try await activate() else { return }
        try await store.resume(sessionID: liveSession.id, at: date)
        liveSession.open(at: date)
        phase = .recording(.searching)
        wasStationary = false
        clearOperationFailure()
        startUpdates()
      } catch is CancellationError {
        locationSession.deactivate()
      } catch { report(error) }
    }
  }

  public func retryLocationUpdates() async {
    await queue.run { [self] in
      guard case .recording(let status) = phase, pendingTransition == nil else { return }
      let waitingForAccess: Bool
      if case .waitingForAccess = status {
        waitingForAccess = true
      } else {
        waitingForAccess = false
      }
      guard updatesTask == nil || waitingForAccess else { return }
      isBusy = true
      defer { isBusy = false }
      stopUpdates()
      if !waitingForAccess { phase = .recording(.searching) }
      do {
        if waitingForAccess {
          try await interruptIfOpen()
          // A previous activation may have cached a grant preceding the Settings change.
          locationSession.deactivate()
        }
        guard try await activate() else { return }
        phase = .recording(.searching)
        clearOperationFailure()
        startUpdates()
      } catch is CancellationError {
        locationSession.deactivate()
      } catch { report(error) }
    }
  }

  /// Saves pending points, e.g. when the app moves to the background.
  ///
  /// Deliberately bypasses the operation queue: a queued activation can wait indefinitely for an
  /// access result, and pending points must still be saved before the app is suspended. This is
  /// safe because store operations do not suspend internally (so a flush cannot interleave with
  /// one) and flushing does not change engine state. Points from events still waiting in the queue
  /// are not included; they are saved with a later batch or transition.
  public func flush() async {
    do {
      try await store.flush()
      clearPointSaveFailure()
    } catch {
      reportPointSaveFailure(error)
    }
  }

  public func clearNotice() { notice = nil }
  public func clearFailure() {
    startFailure = nil
    clearOperationFailure()
  }
  public func clearLastFinishedSession() { lastFinishedSessionID = nil }

  /// Waits until every operation queued so far has completed. Used by tests as a barrier.
  func waitForQueuedOperations() async {
    await queue.run {}
  }

  func activate() async throws -> Bool {
    try await handleActivation { [locationSession] in try await locationSession.activate() }
  }

  /// Applies an access result to the engine state; returns whether access was granted.
  func handleActivation(
    _ obtain: @MainActor () async throws -> LocationAccessResult
  ) async throws -> Bool {
    let result: LocationAccessResult
    do {
      result = try await obtain()
      try Task.checkCancellation()
    } catch is CancellationError { throw CancellationError() } catch {
      log(error)
      if phase == .idle { startFailure = .sensor } else { operationFailure = .sensor }
      return false
    }
    guard case .denied(let issue) = result else { return true }
    if phase == .idle {
      startFailure = .access(issue)
    } else {
      operationFailure = .access(issue)
    }
    if case .recording = phase {
      phase = .recording(.waitingForAccess(issue))
      // A terminated provider may never have delivered accessLost. Denial during retry must
      // still close the last segment rather than counting the denied interval as walking.
      try await interruptIfOpen()
    }
    return false
  }

  func finish(at date: Date) async throws {
    guard let liveSession else { return }
    try await store.finish(sessionID: liveSession.id, at: date, steps: nil)
    lastFinishedSessionID = liveSession.id
    self.liveSession = nil
    pendingTransition = nil
    phase = .idle
    stopUpdates()
    locationSession.deactivate()
    wasStationary = false
  }

  func interruptIfOpen() async throws {
    guard let liveSession, liveSession.record.hasOpenSegment else { return }
    let date = liveSession.lastActivity
    try await store.interruptSegment(sessionID: liveSession.id, at: date, steps: nil)
    liveSession.close(at: date, reason: .interrupted)
  }

  func makeLive(_ record: SessionRecord) -> LiveSession {
    LiveSession(record: record, filter: RouteFilter(configuration: configuration.route))
  }

  func report(_ error: any Error) {
    operationFailure = .persistence
    pointSaveFailed = false
    log(error, logger: persistenceLogger)
  }

  func reportPointSaveFailure(_ error: any Error) {
    // Do not let a point save failure mask a different failure being shown.
    guard operationFailure == nil || pointSaveFailed else {
      log(error, logger: persistenceLogger)
      return
    }
    operationFailure = .persistence
    pointSaveFailed = true
    log(error, logger: persistenceLogger)
  }

  func clearPointSaveFailure() {
    guard pointSaveFailed else { return }
    operationFailure = nil
    pointSaveFailed = false
  }

  func clearOperationFailure() {
    operationFailure = nil
    pointSaveFailed = false
  }

  func log(_ error: any Error, logger: Logger = trackingLogger) {
    logger.error(
      "Tracking operation failed: \(String(describing: error), privacy: .private)")
  }

  isolated deinit {
    updatesTask?.cancel()
    locationSession.deactivate()
  }
}

let trackingLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "Promenade", category: "tracking")

let persistenceLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "Promenade", category: "persistence")
