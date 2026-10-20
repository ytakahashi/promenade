import Domain
import Features
import Foundation
import Persistence
import Sensors
import SwiftData
import Testing
import Tracking
import UIKit

@testable import Promenade

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
    environment.beginRecovery(launch: .background)
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
    environment.beginRecovery(launch: .background)
    #expect(reads == 1)
    #expect(environment.recoveryTask == nil)
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
    environment.beginRecovery(launch: .background)
    environment.retry()
    #expect(reads == 2)
  }

  @Test(arguments: [UIApplication.State.background, .inactive, .active])
  func delegateBeginsRecoverySynchronously(_ state: UIApplication.State) async throws {
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
    delegate.beginRecovery(applicationState: state)
    #expect(delegate.environment === environment)
    #expect(reads == 1)
    #expect(session.begins == (state == .background ? 1 : 0))
    #expect(environment.state == .ready)
    await environment.recoveryTask?.value
    if state == .background {
      #expect(dependencies.engine.phase == .recording(.searching))
      #expect(dependencies.engine.requestFinish(at: Date()))
      await dependencies.engine.confirmPendingTransition()
      #expect(dependencies.engine.phase == .idle)
    } else {
      #expect(
        environment.dependencies?.engine.phase
          == .awaitingRecoveryDecision(lastActivity: start))
    }
  }

  @Test func summaryReaderObservesFinishAfterAnEarlierRead() async throws {
    let environment = try makeEnvironment()
    let dependencies = try #require(environment.dependencies)
    let read = dependencies.readSession
    let id = UUID()
    let start = Date()
    try await dependencies.store.createSession(id: id, startDate: start, timeZone: .current)
    #expect(try read(id)?.state == .recording)
    let end = start.addingTimeInterval(10)
    try await dependencies.store.finish(sessionID: id, at: end)
    let finished = try #require(try read(id))
    #expect(finished.state == .finished)
    #expect(finished.endDate == end)
    #expect(try read(UUID()) == nil)
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
    record = try dependencies.readSession(id: id)
    environment.beginRecovery(launch: .background)
    await session.waitUntilActivating()
    let point = TrackPoint(
      timestamp: start.addingTimeInterval(1), coordinate: Coordinate(latitude: 35, longitude: 139),
      horizontalAccuracy: 5, altitude: 0, verticalAccuracy: -1,
      speed: -1, speedAccuracy: -1, course: -1)
    try await dependencies.store.append(point, sessionID: id)
    #expect(try dependencies.readSession(id: id)?.segments.first?.points.isEmpty == true)
    environment.didBecomeActive()
    let flush = try #require(environment.didEnterBackground())
    await flush.value
    #expect(try dependencies.readSession(id: id)?.segments.first?.points == [point])
    #expect(environment.recoveryTask?.isCancelled == false)
    #expect(session.deactivations == 0)
    session.releaseActivation()
    await environment.recoveryTask?.value
    #expect(environment.state == .ready)
    if dependencies.engine.requestFinish(at: Date()) {
      await dependencies.engine.confirmPendingTransition()
    }
  }

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
