import Domain
import Foundation
import Persistence
import Sensors
import Synchronization
import Testing

@testable import Tracking

@MainActor
final class TrackingHarness {
  static let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)
  let dates = TestDates()
  let session = TestLocationSession()
  let provider = TestLocationProvider()
  let pedometer = TestPedometer()
  let store: ControlledStore
  let engine: TrackingEngine

  /// - Parameter sleep: Defaults to a sleep that never elapses within a test, so timeouts only fire
  ///   when a test opts in.
  init(
    configuration: TrackingConfiguration = .default,
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in
      try await Task.sleep(for: .seconds(3600))
    }
  ) throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    store = ControlledStore(
      base: SwiftDataTrackingStore(container: container, configuration: configuration))
    engine = TrackingEngine(
      store: store, provider: provider, locationSession: session, pedometer: pedometer,
      dates: dates,
      configuration: configuration, timeZone: { TimeZone(secondsFromGMT: 0)! }, sleep: sleep)
  }

  func send(_ point: TrackPoint, stationary: Bool = false) async {
    await engine.receive(.location(point, stationary: stationary))
  }

  func record() async throws -> SessionRecord {
    let id = try #require(engine.liveSession?.id ?? engine.lastFinishedSessionID)
    return try #require(try await store.loadSession(id: id))
  }

  func seed(paused: Bool = false, closed: Bool = false, start: Double = 0) async throws
    -> SessionRecord
  {
    let id = UUID()
    try await store.createSession(id: id, startDate: date(start), timeZone: .current)
    try await store.append(point(start + 1), sessionID: id)
    if paused {
      try await store.pause(sessionID: id, at: date(start + 10), steps: nil)
    } else if closed {
      try await store.interruptSegment(sessionID: id, at: date(start + 1), steps: nil)
    }
    return try #require(try await store.loadSession(id: id))
  }

  func recover(_ records: [SessionRecord], launch: LaunchContext) throws -> Task<Void, Never> {
    try RecoveryCoordinator(engine: engine, dates: dates, readUnfinishedSessions: { records })
      .beginRecovery(launch: launch)
  }
}

@MainActor
final class TestDates: DateProvider {
  var value = TrackingHarness.origin
  func now() -> Date { value }
}

@MainActor
final class TestLocationSession: LocationSession {
  var result: LocationAccessResult = .granted
  var canActivateWithoutPrompt = true
  var error: (any Error)?
  var onActivate: (() -> Void)?
  var gate: TestGate?
  var begins = 0
  var activations = 0
  var deactivations = 0
  func beginActivation() { begins += 1 }
  func activate() async throws -> LocationAccessResult {
    activations += 1
    if let gate { await gate.suspend() }
    try Task.checkCancellation()
    onActivate?()
    if let error { throw error }
    return result
  }
  func deactivate() { deactivations += 1 }
}

final class TestLocationProvider: LocationProvider, Sendable {
  private let streams = Mutex<[AsyncThrowingStream<LocationEvent, any Error>.Continuation]>([])
  func events() -> AsyncThrowingStream<LocationEvent, any Error> {
    AsyncThrowingStream { continuation in streams.withLock { $0.append(continuation) } }
  }
  var subscriptions: Int { streams.withLock { $0.count } }
  func send(_ event: LocationEvent) { _ = streams.withLock { $0.last?.yield(event) } }
  func finish(error: (any Error)? = nil) { streams.withLock { $0.last?.finish(throwing: error) } }
}

/// Counts no steps unless a test sets `count`, so tests without step expectations are unaffected.
final class TestPedometer: PedometerProvider, Sendable {
  private struct State {
    var count: (@Sendable (Date, Date) -> Int?)?
    var blocksQueries = false
    var queries: [ClosedRange<Date>] = []
    var liveStarts: [Date] = []
    var live: AsyncStream<Int>.Continuation?
    var activeLiveStreams = 0
  }
  private let state = Mutex(State())

  var access: MotionAccess { .allowed }
  var queries: [ClosedRange<Date>] { state.withLock { $0.queries } }
  var liveStarts: [Date] { state.withLock { $0.liveStarts } }
  var activeLiveStreams: Int { state.withLock { $0.activeLiveStreams } }

  /// Counts one step per second of the queried interval.
  func countSeconds() { state.withLock { $0.count = { Int($1.timeIntervalSince($0)) } } }
  /// Queries never return, so only the engine's timeout can complete them.
  func blockQueries() { state.withLock { $0.blocksQueries = true } }
  /// Sends a cumulative value to the latest live subscription.
  func sendLive(_ steps: Int) { _ = state.withLock { $0.live?.yield(steps) } }

  func steps(from start: Date, to end: Date) async -> Int? {
    let (count, blocks) = state.withLock {
      $0.queries.append(start...end)
      return ($0.count, $0.blocksQueries)
    }
    if blocks { try? await Task.sleep(for: .seconds(3600)) }
    return count?(start, end)
  }

  func liveSteps(from start: Date) -> AsyncStream<Int> {
    AsyncStream { continuation in
      state.withLock {
        $0.liveStarts.append(start)
        $0.live = continuation
        $0.activeLiveStreams += 1
      }
      continuation.onTermination = { [weak self] _ in
        self?.state.withLock { $0.activeLiveStreams -= 1 }
      }
    }
  }
}

/// A controllable await boundary verifies serialization while the underlying store remains real.
actor TestGate {
  private var blocked: CheckedContinuation<Void, Never>?
  private var arrived = false
  private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
  func suspend() async {
    await withCheckedContinuation {
      blocked = $0
      arrived = true
      for waiter in arrivalWaiters { waiter.resume() }
      arrivalWaiters.removeAll()
    }
  }
  func waitUntilBlocked() async {
    if !arrived { await withCheckedContinuation { arrivalWaiters.append($0) } }
  }
  func release() {
    blocked?.resume()
    blocked = nil
  }
}

actor ControlledStore: TrackingStore {
  enum Operation: Sendable, Equatable {
    case create, append, pause, resume, split, interrupt, open, finish, discard, flush, load
  }
  enum Failure: Error { case injected }
  let base: SwiftDataTrackingStore
  private var nextFailure: Operation?
  private var pendingAppendFailure = false
  private var suspension: (Operation, TestGate)?
  private(set) var calls: [Operation] = []

  init(base: SwiftDataTrackingStore) { self.base = base }
  func failNext(_ operation: Operation) { nextFailure = operation }
  func failAcceptedAppend() { pendingAppendFailure = true }
  func reportNextAppendSaved() { nextAppendSaved = true }
  private var nextAppendSaved = false
  func blockNext(_ operation: Operation, on gate: TestGate) { suspension = (operation, gate) }
  private func before(_ operation: Operation) async throws {
    calls.append(operation)
    if let (target, gate) = suspension, target == operation {
      suspension = nil
      await gate.suspend()
    }
    if nextFailure == operation {
      nextFailure = nil
      throw Failure.injected
    }
  }
  func createSession(id: UUID, startDate: Date, timeZone: TimeZone) async throws {
    try await before(.create)
    try await base.createSession(id: id, startDate: startDate, timeZone: timeZone)
  }
  @discardableResult
  func append(_ point: TrackPoint, sessionID: UUID) async throws -> PointAppendResult {
    try await before(.append)
    let result = try await base.append(point, sessionID: sessionID)
    if pendingAppendFailure {
      pendingAppendFailure = false
      return .pendingSaveFailure(Failure.injected)
    }
    if nextAppendSaved {
      nextAppendSaved = false
      return .saved
    }
    return result
  }
  func pause(sessionID: UUID, at date: Date, steps: Int?) async throws {
    try await before(.pause)
    try await base.pause(sessionID: sessionID, at: date, steps: steps)
  }
  func resume(sessionID: UUID, at date: Date) async throws {
    try await before(.resume)
    try await base.resume(sessionID: sessionID, at: date)
  }
  func splitSegment(
    sessionID: UUID, closingAt: Date, reason: SegmentEndReason, steps: Int?, nextStart: Date
  ) async throws {
    try await before(.split)
    try await base.splitSegment(
      sessionID: sessionID, closingAt: closingAt, reason: reason, steps: steps,
      nextStart: nextStart)
  }
  func interruptSegment(sessionID: UUID, at date: Date, steps: Int?) async throws {
    try await before(.interrupt)
    try await base.interruptSegment(sessionID: sessionID, at: date, steps: steps)
  }
  func openSegment(sessionID: UUID, at date: Date) async throws {
    try await before(.open)
    try await base.openSegment(sessionID: sessionID, at: date)
  }
  func finish(sessionID: UUID, at date: Date, steps: Int?) async throws {
    try await before(.finish)
    try await base.finish(sessionID: sessionID, at: date, steps: steps)
  }
  func discard(sessionID: UUID) async throws {
    try await before(.discard)
    try await base.discard(sessionID: sessionID)
  }
  func flush() async throws {
    try await before(.flush)
    try await base.flush()
  }
  func loadSession(id: UUID) async throws -> SessionRecord? {
    try await before(.load)
    return try await base.loadSession(id: id)
  }
}

func date(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds) }
func point(_ seconds: Double, accuracy: Double = 5, north: Double = 0) -> TrackPoint {
  TrackPoint(
    timestamp: date(seconds), coordinate: Coordinate(latitude: 35 + north, longitude: 139),
    horizontalAccuracy: accuracy, altitude: 0, verticalAccuracy: -1, speed: -1, speedAccuracy: -1,
    course: -1)
}

/// Bounded scheduler polling is only used for observing the asynchronous subscription boundary.
@MainActor
func eventually(
  _ predicate: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation
) async {
  for _ in 0..<10_000 {
    if predicate() { return }
    await Task.yield()
  }
  Issue.record("Condition did not become true", sourceLocation: sourceLocation)
}
