import CoreLocation
import Testing

@testable import Sensors

@MainActor
struct CoreLocationSessionTests {
  @Test func beginsSynchronouslyReusesResourcesAndDeactivatesOnce() async throws {
    let resources = FakeResources()
    var creations = 0
    let session = CoreLocationSession {
      creations += 1
      return resources
    }
    session.beginActivation()
    #expect(creations == 1)
    session.beginActivation()
    #expect(creations == 1)
    resources.continuation.yield(.granted)
    #expect(try await session.activate() == .granted)
    #expect(try await session.activate() == .granted)
    #expect(resources.invalidations == 0)
    session.deactivate()
    session.deactivate()
    #expect(resources.invalidations == 1)
  }

  @Test func denialAndDiagnosticFailureReleaseResourcesAndAllowRetry() async throws {
    let first = FakeResources()
    let second = FakeResources()
    var creations = 0
    let session = CoreLocationSession {
      creations += 1
      return creations == 1 ? first : second
    }
    first.continuation.yield(.denied(.accuracyLimited))
    #expect(try await session.activate() == .denied(.accuracyLimited))
    #expect(first.invalidations == 1)
    second.continuation.finish()
    await #expect(throws: LocationSensorError.diagnosticsEnded) {
      try await session.activate()
    }
    #expect(second.invalidations == 1)
  }

  @Test func cancellationEndsPendingActivation() async throws {
    let resources = FakeResources()
    let session = CoreLocationSession { resources }
    session.beginActivation()
    let (started, continuation) = AsyncStream<Void>.makeStream()
    let waiter = Task {
      continuation.yield(())
      return try await session.activate()
    }
    for await _ in started { break }
    await resources.waitUntilReading()
    waiter.cancel()
    await #expect(throws: CancellationError.self) { try await waiter.value }
    #expect(resources.invalidations == 1)
  }

  @Test func lateCompletionCannotInvalidateSuccessor() async throws {
    let first = FakeResources()
    let second = FakeResources()
    var creations = 0
    let session = CoreLocationSession {
      creations += 1
      return creations == 1 ? first : second
    }
    session.beginActivation()
    await first.waitUntilReading()
    session.deactivate()
    session.beginActivation()
    first.continuation.yield(.denied(.denied))
    second.continuation.yield(.granted)
    #expect(try await session.activate() == .granted)
    #expect(first.invalidations == 1)
    #expect(second.invalidations == 0)
    session.deactivate()
  }

  @Test(arguments: [
    (CLAuthorizationStatus.authorizedWhenInUse, true),
    (.authorizedAlways, true),
    (.notDetermined, false),
    (.denied, false),
    (.restricted, false),
  ])
  func activationWithoutPromptRequiresGrantedAuthorization(
    _ status: CLAuthorizationStatus, _ expected: Bool
  ) {
    let session = CoreLocationSession(
      makeResources: { FakeResources() }, authorizationStatus: { status })
    #expect(session.canActivateWithoutPrompt == expected)
  }

  @Test func releasingSessionInvalidatesResources() {
    let resources = FakeResources()
    var session: CoreLocationSession? = CoreLocationSession { resources }
    session?.beginActivation()
    session = nil
    #expect(resources.invalidations == 1)
  }
}

@MainActor
private final class FakeResources: LocationSessionResources {
  let stream: AsyncThrowingStream<LocationAccessResult, any Error>
  let continuation: AsyncThrowingStream<LocationAccessResult, any Error>.Continuation
  var invalidations = 0
  private var reading = false
  private var readingWaiters: [CheckedContinuation<Void, Never>] = []

  init() {
    (stream, continuation) = AsyncThrowingStream.makeStream()
  }

  func accessResult() async throws -> LocationAccessResult {
    reading = true
    for waiter in readingWaiters { waiter.resume() }
    readingWaiters.removeAll()
    for try await result in stream { return result }
    try Task.checkCancellation()
    throw LocationSensorError.diagnosticsEnded
  }

  func waitUntilReading() async {
    if !reading { await withCheckedContinuation { readingWaiters.append($0) } }
  }

  func invalidate() { invalidations += 1 }
}
