import Domain
import Foundation
import Persistence
import SwiftData
import Synchronization
import Testing
import Tracking
import UIKit

@testable import Features
@testable import Promenade
@testable import Sensors

@MainActor
struct AppEnvironmentTests {
  enum Failure: Error { case injected }

  @Test func defaultDelegateIsInertWhileHostingUnitTests() throws {
    // This test process hosts unit tests, so the default initializer must take the inert path.
    let delegate = AppDelegate()
    let container = try #require(delegate.environment.dependencies?.container)
    let inMemory = container.configurations.allSatisfy { $0.isStoredInMemoryOnly }
    #expect(inMemory)
    _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
    #expect(delegate.environment.recoveryTask == nil)
    #expect(delegate.environment.state == .waitingForLaunch)
  }

  @Test func unexpectedSensorSetupErrorIsNotReportedAsReplayData() {
    let environment = AppEnvironment(
      makeContainer: { try ModelContainerFactory.make(inMemory: true) },
      makeSensors: { throw Failure.injected })
    guard case .failed(let failure) = environment.state else {
      Issue.record("Expected a sensor setup failure")
      return
    }
    #expect(failure.kind == .sensors)
    #expect(environment.dependencies == nil)
  }

  @Test func containerRetryPreservesSuccessfullyCreatedSensors() async throws {
    let session = StubLocationSession()
    var containers = 0
    var sensors = 0
    let environment = AppEnvironment(
      makeContainer: {
        containers += 1
        if containers == 1 { throw Failure.injected }
        return try ModelContainerFactory.make(inMemory: true)
      },
      makeSensors: {
        sensors += 1
        return AppSensors(provider: IdleProvider(), session: session, authorization: nil)
      })
    guard case .failed(let failure) = environment.state else {
      Issue.record("Expected a storage failure")
      return
    }
    #expect(failure.kind == .storage)
    environment.beginRecovery(locationLaunch: false)
    #expect(containers == 1)
    #expect(environment.recoveryTask == nil)
    environment.retry()
    await environment.recoveryTask?.value
    #expect(environment.state == .ready)
    #expect(containers == 2)
    #expect(sensors == 1)
    #expect(session.begins == 0)
    environment.retry()
    #expect(containers == 2)
  }

  @Test func fetchRetryKeepsEngineAndUsesForegroundPolicy() async throws {
    var reads = 0
    var containers = 0
    let record = SessionRecord(
      id: UUID(), startDate: Date(), state: .recording,
      timeZoneIdentifier: "UTC", segments: [])
    let session = StubLocationSession()
    let environment = AppEnvironment(
      makeContainer: {
        containers += 1
        return try ModelContainerFactory.make(inMemory: true)
      },
      makeSensors: { AppSensors(provider: IdleProvider(), session: session, authorization: nil) },
      readUnfinished: { _ in
        reads += 1
        if reads == 1 { throw Failure.injected }
        return [record]
      })
    let engine = try #require(environment.dependencies?.engine)
    environment.beginRecovery(locationLaunch: false)
    #expect(reads == 1)
    #expect(environment.recoveryTask == nil)
    #expect(environment.launchResolver == nil)
    #expect(engine.phase == .idle)
    guard case .failed(let failure) = environment.state else {
      Issue.record("Expected a recovery read failure")
      return
    }
    #expect(failure.kind == .recovery)
    environment.retry()
    await environment.recoveryTask?.value
    #expect(environment.dependencies?.engine === engine)
    #expect(containers == 1)
    #expect(reads == 2)
    #expect(engine.phase == .awaitingRecoveryDecision(lastActivity: record.startDate))
    #expect(session.begins == 0)
    #expect(environment.launchResolver?.reason == .retry)
    environment.beginRecovery(launch: .background)
    environment.retry()
    #expect(reads == 2)
  }

  @Test(arguments: [UIApplication.State.background, .inactive, .active], [false, true])
  func delegateBeginsRecoverySynchronously(
    _ state: UIApplication.State, hasLocationOption: Bool
  ) async throws {
    let session = StubLocationSession()
    var reads = 0
    let start = Date()
    let id = UUID()
    let environment = AppEnvironment(
      makeContainer: { try ModelContainerFactory.make(inMemory: true) },
      makeSensors: { AppSensors(provider: IdleProvider(), session: session, authorization: nil) },
      readUnfinished: { container in
        reads += 1
        return try AppDependencies.readUnfinishedSessions(container: container)
      })
    let dependencies = try #require(environment.dependencies)
    try await dependencies.store.createSession(id: id, startDate: start, timeZone: .current)
    let delegate = AppDelegate(environment: environment)
    #expect(reads == 0)
    #expect(session.begins == 0)
    delegate.beginRecovery(applicationState: state, hasLocationOption: hasLocationOption)
    #expect(delegate.environment === environment)
    #expect(reads == 1)
    #expect(session.begins == 1)
    #expect(environment.state == .ready)
    if !hasLocationOption {
      #expect(environment.launchResolver?.context == nil)
      // The initial background Scene value must flush without settling or cancelling recovery.
      await environment.didEnterBackground()?.value
      #expect(environment.dependencies?.engine.phase == .idle)
      #expect(environment.recoveryTask?.isCancelled == false)
      environment.didBecomeActive()
    }
    await environment.recoveryTask?.value
    environment.didBecomeActive()
    delegate.beginRecovery(applicationState: state, hasLocationOption: hasLocationOption)
    #expect(reads == 1)
    if hasLocationOption {
      #expect(dependencies.engine.phase == .recording(.searching))
      #expect(session.deactivations == 0)
      #expect(dependencies.engine.requestFinish(at: Date()))
      await dependencies.engine.confirmPendingTransition()
      #expect(dependencies.engine.phase == .idle)
    } else {
      #expect(session.deactivations == 1)
      #expect(environment.launchResolver?.reason == .sceneActive)
      #expect(
        environment.dependencies?.engine.phase
          == .awaitingRecoveryDecision(lastActivity: start))
    }
  }

  @Test func activeObservedBeforeRecoveryIsNotMissed() async throws {
    let session = StubLocationSession()
    let record = SessionRecord(
      id: UUID(), startDate: Date(), state: .recording,
      timeZoneIdentifier: "UTC", segments: [])
    let environment = AppEnvironment(
      makeContainer: { try ModelContainerFactory.make(inMemory: true) },
      makeSensors: { AppSensors(provider: IdleProvider(), session: session, authorization: nil) },
      readUnfinished: { _ in [record] })
    environment.didBecomeActive()
    AppDelegate(environment: environment).beginRecovery(applicationState: .background)
    await environment.recoveryTask?.value
    #expect(environment.launchResolver?.context == .foreground)
    #expect(
      environment.dependencies?.engine.phase
        == .awaitingRecoveryDecision(lastActivity: record.startDate))
    #expect(session.begins == 0)
  }

  @Test func applicationCallbackForwardsLocationLaunchOption() async throws {
    let environment = try makeEnvironment()
    let delegate = AppDelegate(environment: environment)
    let dependencies = try #require(environment.dependencies)
    try await dependencies.store.createSession(id: UUID(), startDate: Date(), timeZone: .current)
    // An already-active scene must not replace an explicit location launch reason.
    environment.didBecomeActive()
    #expect(
      delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: [.location: true]))
    #expect(environment.launchResolver?.context == .background)
    #expect(environment.launchResolver?.reason == .locationOption)
    await environment.recoveryTask?.value
    #expect(dependencies.engine.phase == .recording(.searching))
    #expect(dependencies.engine.requestFinish(at: Date()))
    await dependencies.engine.confirmPendingTransition()
  }

  @Test func deadlineResumesAndLateActiveDoesNotRepeatRecovery() async throws {
    let session = StubLocationSession()
    var reads = 0
    var timeout: TimeInterval?
    let environment = AppEnvironment(
      makeContainer: { try ModelContainerFactory.make(inMemory: true) },
      makeSensors: { AppSensors(provider: IdleProvider(), session: session, authorization: nil) },
      readUnfinished: {
        reads += 1
        return try AppDependencies.readUnfinishedSessions(container: $0)
      },
      makeLaunchResolver: {
        timeout = $0
        return LaunchContextResolver(timeout: $0, sleepUntil: { _ in })
      })
    let dependencies = try #require(environment.dependencies)
    try await dependencies.store.createSession(id: UUID(), startDate: Date(), timeZone: .current)
    environment.beginRecovery(locationLaunch: false)
    await environment.recoveryTask?.value
    #expect(timeout == environment.configuration.launchContextTimeout)
    #expect(environment.launchResolver?.reason == .deadline)
    #expect(dependencies.engine.phase == .recording(.searching))
    environment.didBecomeActive()
    environment.beginRecovery(locationLaunch: false)
    environment.retry()
    #expect(reads == 1)
    #expect(session.begins == 1)
    #expect(dependencies.engine.phase == .recording(.searching))
    #expect(dependencies.engine.requestFinish(at: Date()))
    await dependencies.engine.confirmPendingTransition()
  }

  @Test func summaryReaderObservesFinishAfterAnEarlierRead() async throws {
    let environment = try makeEnvironment()
    let dependencies = try #require(environment.dependencies)
    let read = dependencies.readSession
    let id = UUID()
    let start = Date()
    try await dependencies.store.createSession(id: id, startDate: start, timeZone: .current)
    #expect(try await read(id)?.state == .recording)
    let points = (1...3).map { index in
      TrackPoint(
        timestamp: start.addingTimeInterval(Double(index) * 5),
        // About 7 m every 5 seconds: beyond the 5 m accuracy and at a walking speed, so the
        // route filter accepts every point.
        coordinate: Coordinate(latitude: 35 + Double(index) * 0.000063, longitude: 139),
        horizontalAccuracy: 5, altitude: 0, verticalAccuracy: -1, speed: -1, speedAccuracy: -1,
        course: -1)
    }
    for point in points { try await dependencies.store.append(point, sessionID: id) }
    let end = start.addingTimeInterval(20)
    try await dependencies.store.finish(sessionID: id, at: end, steps: nil)

    // Finishing saves buffered points; a fresh read context must see them with the final state.
    let finished = try #require(try await read(id))
    #expect(finished.state == .finished)
    #expect(finished.endDate == end)
    #expect(finished.segments.last?.points.last == points.last)
    let model = SessionSummaryModel(
      sessionID: id, route: environment.configuration.route, read: read)
    await model.load()
    guard case .loaded(let summary) = model.state else {
      Issue.record("Expected a loaded summary")
      return
    }
    #expect(summary.metrics.timing.walking == 20)
    #expect(summary.metrics.distance > 10)
    #expect(summary.map.segments.first?.coordinates.count == 3)
    #expect(try await read(UUID()) == nil)
  }

  @Test(.timeLimit(.minutes(1)))
  func backgroundFlushDoesNotCancelOrWaitForRecoveryAuthorization() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let session = StubLocationSession()
    session.holdActivation = true
    var record: SessionRecord?
    let environment = AppEnvironment(
      makeContainer: { container },
      makeSensors: { AppSensors(provider: IdleProvider(), session: session, authorization: nil) },
      readUnfinished: { _ in [try #require(record)] })
    let dependencies = try #require(environment.dependencies)
    let id = UUID()
    let start = Date().addingTimeInterval(-10)
    try await dependencies.store.createSession(id: id, startDate: start, timeZone: .current)
    record = try await dependencies.readSession(id: id)
    environment.beginRecovery(launch: .background)
    await session.waitUntilActivating()
    let point = TrackPoint(
      timestamp: start.addingTimeInterval(1), coordinate: Coordinate(latitude: 35, longitude: 139),
      horizontalAccuracy: 5, altitude: 0, verticalAccuracy: -1,
      speed: -1, speedAccuracy: -1, course: -1)
    try await dependencies.store.append(point, sessionID: id)
    #expect(try await dependencies.readSession(id: id)?.segments.first?.points.isEmpty == true)
    environment.didBecomeActive()
    let flush = try #require(environment.didEnterBackground())
    await flush.value
    #expect(try await dependencies.readSession(id: id)?.segments.first?.points == [point])
    #expect(environment.recoveryTask?.isCancelled == false)
    #expect(session.deactivations == 0)
    session.releaseActivation()
    await environment.recoveryTask?.value
    #expect(environment.state == .ready)
    if dependencies.engine.requestFinish(at: Date()) {
      await dependencies.engine.confirmPendingTransition()
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func becomingActiveRechecksLocationServices() async throws {
    let enabled = Mutex(true)
    let monitor = LocationAuthorizationMonitor(readServicesEnabled: { enabled.withLock { $0 } })
    let environment = AppEnvironment(
      makeContainer: { try ModelContainerFactory.make(inMemory: true) },
      makeSensors: {
        AppSensors(provider: IdleProvider(), session: StubLocationSession(), authorization: monitor)
      })
    await monitor.refreshServicesEnabled()
    #expect(environment.locationAccess != .servicesDisabled)
    enabled.withLock { $0 = false }
    environment.didBecomeActive()
    while environment.locationAccess != .servicesDisabled { await Task.yield() }
  }

  #if DEBUG
    @Test func invalidStoreOptionNeverFallsBackToTheRegularStore() {
      let environment = AppEnvironment(
        makeContainer: {
          try AppEnvironment.makeContainer(arguments: ["-StoreURL", "walks.store"])
        },
        makeSensors: {
          AppSensors(provider: IdleProvider(), session: StubLocationSession(), authorization: nil)
        })
      guard case .failed(let failure) = environment.state else {
        Issue.record("Expected a storage option failure")
        return
      }
      #expect(failure.kind == .storeArguments)
      #expect(environment.dependencies == nil)
    }

    @Test func storeOptionKeepsWalksInItsOwnFile() async throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let arguments = ["-StoreURL", directory.appendingPathComponent("walks.store").path]
      let id = UUID()
      do {
        let container = try AppEnvironment.makeContainer(arguments: arguments)
        let store = SwiftDataTrackingStore(container: container, configuration: .default)
        try await store.createSession(id: id, startDate: Date(), timeZone: .current)
      }
      let reopened = try AppEnvironment.makeContainer(arguments: arguments)
      #expect(try AppDependencies.readUnfinishedSessions(container: reopened).map(\.id) == [id])
    }
  #endif

  #if DEBUG
    @Test func replayFailuresNeverFallBackToRealGPS() throws {
      for (arguments, kind) in [
        (["-ReplaySpeed", "2"], StartupFailureKind.replayArguments),
        (["-ReplayGPX", "/no-such-replay-file.gpx"], .replayFile),
      ] {
        var containers = 0
        let environment = AppEnvironment(
          makeContainer: {
            containers += 1
            return try ModelContainerFactory.make(inMemory: true)
          }, makeSensors: { try AppSensors.make(arguments: arguments) })
        guard case .failed(let failure) = environment.state else {
          Issue.record("Expected Replay initialization to fail")
          continue
        }
        #expect(failure.kind == kind)
        #expect(environment.dependencies == nil)
        #expect(containers == 0)
      }
    }

    @Test func replayIgnoresDevicePermissionsAndRetriesFileReading() throws {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString + ".gpx")
      defer { try? FileManager.default.removeItem(at: url) }
      let environment = AppEnvironment(
        makeContainer: { try ModelContainerFactory.make(inMemory: true) },
        makeSensors: { try AppSensors.make(arguments: ["-ReplayGPX", url.path]) })
      #expect(environment.dependencies == nil)
      try Data("invalid XML".utf8).write(to: url)
      environment.retry()
      guard case .failed(let failure) = environment.state else {
        Issue.record("Expected invalid GPX data")
        return
      }
      #expect(failure.kind == .replayData)
      try Data(
        """
        <gpx><trk><trkseg><trkpt lat="35" lon="139">
        <time>2026-10-20T00:00:00Z</time></trkpt></trkseg></trk></gpx>
        """.utf8
      ).write(to: url)
      environment.retry()
      #expect(environment.state == .ready)
      #expect(environment.locationAccess == .available)
    }
  #endif

  @Test(arguments: [false, true])
  func refreshWaitsForRecoveryAndActiveRegardlessOfOrder(activeFirst: Bool) async throws {
    var reads = 0
    let environment = AppEnvironment(
      makeContainer: { try ModelContainerFactory.make(inMemory: true) },
      makeSensors: {
        AppSensors(provider: IdleProvider(), session: StubLocationSession(), authorization: nil)
      },
      readRecomputeIDs: { _ in
        reads += 1
        return [UUID()]
      })
    if activeFirst { environment.didBecomeActive() }
    #expect(environment.refreshTask == nil)
    environment.beginRecovery(launch: .foreground)
    // Ready is published before recovery finishes and must not start recomputation.
    #expect(environment.state == .ready)
    #expect(environment.refreshTask == nil)
    await environment.recoveryCompletionTask?.value
    if !activeFirst {
      #expect(environment.refreshTask == nil)
      environment.didBecomeActive()
    }
    let task = try #require(environment.refreshTask)
    await task.value
    #expect(reads == 1)
    await environment.didEnterBackground()?.value
    environment.didBecomeActive()
    await environment.refreshTask?.value
    #expect(reads == 1)
  }

  @Test func backgroundCancelsRefreshWithoutRestart() async throws {
    var reads = 0
    let environment = AppEnvironment(
      makeContainer: { try ModelContainerFactory.make(inMemory: true) },
      makeSensors: {
        AppSensors(provider: IdleProvider(), session: StubLocationSession(), authorization: nil)
      },
      readRecomputeIDs: { _ in
        reads += 1
        return []
      })
    environment.beginRecovery(launch: .foreground)
    await environment.recoveryCompletionTask?.value
    environment.didBecomeActive()
    let refresh = try #require(environment.refreshTask)
    // Cancel before the scheduled task runs, covering an active/background transition in one turn.
    let flush = environment.didEnterBackground()
    #expect(refresh.isCancelled)
    await refresh.value
    await flush?.value
    environment.didBecomeActive()
    await environment.refreshTask?.value
    #expect(reads == 0)
    #expect(environment.refreshTask?.isCancelled == true)
  }

  @Test func startInProgressEndsRefreshBeforeReading() async throws {
    let session = StubLocationSession()
    var reads = 0
    let environment = AppEnvironment(
      makeContainer: { try ModelContainerFactory.make(inMemory: true) },
      makeSensors: { AppSensors(provider: IdleProvider(), session: session, authorization: nil) },
      readRecomputeIDs: { _ in
        reads += 1
        return []
      })
    let dependencies = try #require(environment.dependencies)
    environment.beginRecovery(launch: .foreground)
    await environment.recoveryCompletionTask?.value
    session.holdActivation = true
    let start = Task { await dependencies.engine.start() }
    await session.waitUntilActivating()
    // The engine stays idle until the session is created, so only isBusy reveals the start.
    #expect(dependencies.engine.phase == .idle)
    #expect(dependencies.engine.isBusy)
    environment.didBecomeActive()
    await environment.refreshTask?.value
    #expect(reads == 0)
    session.releaseActivation()
    await start.value
  }

  @Test func backgroundAfterActiveWhileRecoveringDefersRefreshUntilNextActive() async throws {
    let session = StubLocationSession()
    session.holdActivation = true
    let container = try ModelContainerFactory.make(inMemory: true)
    var reads = 0
    let environment = AppEnvironment(
      makeContainer: { container },
      makeSensors: { AppSensors(provider: IdleProvider(), session: session, authorization: nil) },
      readRecomputeIDs: { _ in
        reads += 1
        return []
      })
    let dependencies = try #require(environment.dependencies)
    try await dependencies.store.createSession(id: UUID(), startDate: Date(), timeZone: .current)
    environment.beginRecovery(launch: .background)
    await session.waitUntilActivating()
    environment.didBecomeActive()
    await environment.didEnterBackground()?.value
    session.releaseActivation()
    await environment.recoveryCompletionTask?.value
    #expect(environment.refreshTask == nil)
    #expect(reads == 0)
    environment.didBecomeActive()
    await environment.refreshTask?.value
    // A restored recording consumes the attempt without fetching. Finishing must not retry it.
    #expect(environment.refreshTask != nil)
    #expect(reads == 0)
    #expect(dependencies.engine.requestFinish(at: Date()))
    await dependencies.engine.confirmPendingTransition()
    await environment.didEnterBackground()?.value
    environment.didBecomeActive()
    await environment.refreshTask?.value
    #expect(reads == 0)
  }

  @Test func failedRecoveryReadDoesNotConsumeRefreshBeforeRetry() async throws {
    var recoveryReads = 0
    var refreshReads = 0
    let environment = AppEnvironment(
      makeContainer: { try ModelContainerFactory.make(inMemory: true) },
      makeSensors: {
        AppSensors(provider: IdleProvider(), session: StubLocationSession(), authorization: nil)
      },
      readUnfinished: { _ in
        recoveryReads += 1
        if recoveryReads == 1 { throw Failure.injected }
        return []
      },
      readRecomputeIDs: { _ in
        refreshReads += 1
        return []
      })
    environment.didBecomeActive()
    environment.beginRecovery(launch: .foreground)
    #expect(environment.refreshTask == nil)
    environment.retry()
    await environment.recoveryCompletionTask?.value
    await environment.refreshTask?.value
    #expect(refreshReads == 1)
  }

  #if DEBUG
    @Test(arguments: [
      ["-SeedSessions", "3"], ["-SeedSessions", "0"], ["-SeedSessions"],
      ["-SeedSessions", "1", "-SeedSessions", "2"],
    ])
    func invalidSeedOptionsFailBeforeCreatingDependencies(arguments: [String]) {
      let environment = AppEnvironment(
        makeContainer: { try AppEnvironment.makeContainer(arguments: arguments) },
        makeSensors: {
          AppSensors(provider: IdleProvider(), session: StubLocationSession(), authorization: nil)
        })
      guard case .failed(let failure) = environment.state else {
        Issue.record("Expected a seed argument failure")
        return
      }
      #expect(failure.kind == .storeArguments)
      #expect(environment.dependencies == nil)
      #expect(environment.recoveryTask == nil)
      if arguments == ["-SeedSessions", "3"] {
        #expect(failure.detail == "-SeedSessions requires -StoreURL.")
      }
    }

    @Test func seedIsVisibleBeforeRecoveryAndReopeningDoesNotAddSessions() async throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let arguments = [
        "-StoreURL", directory.appendingPathComponent("walks.store").path, "-SeedSessions", "5",
      ]
      let environment = AppEnvironment(
        makeContainer: { try AppEnvironment.makeContainer(arguments: arguments) },
        makeSensors: {
          AppSensors(provider: IdleProvider(), session: StubLocationSession(), authorization: nil)
        },
        readUnfinished: { container in
          let reader = SessionReader(context: ModelContext(container))
          #expect(try reader.finishedSessions().count == 5)
          #expect(try reader.sessionIDsNeedingRecompute().isEmpty)
          return try reader.unfinishedSessions()
        })
      let dependencies = try #require(environment.dependencies)
      let before = try dependencies.listSessions()
      #expect(before.count == 5)
      environment.beginRecovery(launch: .foreground)
      await environment.recoveryCompletionTask?.value
      let reopened = try AppEnvironment.makeContainer(arguments: arguments)
      #expect(try SessionReader(context: ModelContext(reopened)).finishedSessions() == before)
    }
  #endif

  private func makeEnvironment() throws -> AppEnvironment {
    AppEnvironment(
      makeContainer: { try ModelContainerFactory.make(inMemory: true) },
      makeSensors: {
        AppSensors(provider: IdleProvider(), session: StubLocationSession(), authorization: nil)
      })
  }
}

nonisolated private struct IdleProvider: LocationProvider {
  func events() -> AsyncThrowingStream<LocationEvent, any Error> {
    AsyncThrowingStream { _ in }
  }
}

@MainActor
private final class StubLocationSession: LocationSession {
  var canActivateWithoutPrompt = true
  var begins = 0
  var deactivations = 0
  var holdActivation = false
  private var activation: CheckedContinuation<Void, Never>?
  private var waiting: CheckedContinuation<Void, Never>?

  func beginActivation() { begins += 1 }
  func activate() async throws -> LocationAccessResult {
    if holdActivation {
      await withCheckedContinuation { continuation in
        activation = continuation
        waiting?.resume()
        waiting = nil
      }
    }
    try Task.checkCancellation()
    return .granted
  }
  func deactivate() { deactivations += 1 }
  func waitUntilActivating() async {
    if activation == nil { await withCheckedContinuation { waiting = $0 } }
  }
  func releaseActivation() {
    activation?.resume()
    activation = nil
  }
}
