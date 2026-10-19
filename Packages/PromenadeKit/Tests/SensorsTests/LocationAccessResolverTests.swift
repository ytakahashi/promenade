import CoreLocation
import Testing

@testable import Sensors

@MainActor
struct LocationAccessResolverTests {
  @Test func authorizationChangeAfterClearDiagnosticResolvesGrant() async throws {
    let harness = Harness(status: .notDetermined)
    let resolution = harness.resolve()
    harness.diagnostics.yield(LocationDiagnostics())
    // The clear diagnostic is evaluated while authorization is still undecided.
    await harness.waitForEvaluations(1)
    harness.status = .authorizedWhenInUse
    harness.changes.yield()
    #expect(try await resolution.value == .granted)
  }

  @Test func authorizationChangeBeforeFirstDiagnosticWaitsForIt() async throws {
    let harness = Harness(status: .authorizedWhenInUse)
    let resolution = harness.resolve()
    harness.changes.yield()
    harness.diagnostics.yield(LocationDiagnostics())
    #expect(try await resolution.value == .granted)
  }

  @Test func reducedAccuracyWaitsUntilFullAccuracy() async throws {
    let harness = Harness(status: .authorizedWhenInUse, accuracy: .reducedAccuracy)
    let resolution = harness.resolve()
    harness.diagnostics.yield(LocationDiagnostics())
    await harness.waitForEvaluations(1)
    harness.accuracy = .fullAccuracy
    harness.changes.yield()
    #expect(try await resolution.value == .granted)
  }

  @Test func reportedDenialResolvesWithoutAuthorizationChange() async throws {
    let harness = Harness(status: .notDetermined)
    let resolution = harness.resolve()
    harness.diagnostics.yield(LocationDiagnostics(requestInProgress: true))
    harness.diagnostics.yield(LocationDiagnostics(denied: true))
    #expect(try await resolution.value == .denied(.denied))
  }

  @Test func endedDiagnosticsThrow() async {
    let harness = Harness(status: .notDetermined)
    let resolution = harness.resolve()
    harness.diagnostics.finish()
    await #expect(throws: LocationSensorError.diagnosticsEnded) { try await resolution.value }
  }

  @Test func cancellationThrowsCancellationError() async {
    let harness = Harness(status: .notDetermined)
    let resolution = harness.resolve()
    harness.diagnostics.yield(LocationDiagnostics())
    await harness.waitForEvaluations(1)
    resolution.cancel()
    await #expect(throws: CancellationError.self) { try await resolution.value }
  }
}

@MainActor
private final class Harness {
  var status: CLAuthorizationStatus
  var accuracy: CLAccuracyAuthorization
  let diagnostics: AsyncThrowingStream<LocationDiagnostics, any Error>.Continuation
  let changes: AsyncStream<Void>.Continuation
  private let diagnosticStream: AsyncThrowingStream<LocationDiagnostics, any Error>
  private let changeStream: AsyncStream<Void>
  private var evaluations = 0
  private var evaluationWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] =
    []

  init(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization = .fullAccuracy) {
    self.status = status
    self.accuracy = accuracy
    (diagnosticStream, diagnostics) = AsyncThrowingStream.makeStream()
    (changeStream, changes) = AsyncStream.makeStream()
  }

  func resolve() -> Task<LocationAccessResult, any Error> {
    Task {
      try await LocationAccessResolver.resolve(
        diagnostics: diagnosticStream, authorizationChanges: changeStream,
        authorization: { [self] in
          recordEvaluation()
          return (status, accuracy)
        })
    }
  }

  func waitForEvaluations(_ count: Int) async {
    if evaluations >= count { return }
    await withCheckedContinuation { evaluationWaiters.append((count, $0)) }
  }

  private func recordEvaluation() {
    evaluations += 1
    let ready = evaluationWaiters.filter { $0.count <= evaluations }
    evaluationWaiters.removeAll { $0.count <= evaluations }
    for waiter in ready { waiter.continuation.resume() }
  }
}
