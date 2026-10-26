import Foundation
import Persistence
import Testing

@testable import Tracking

@MainActor
struct DerivedDataRefresherTests {
  @Test func runsInOrderOnceAndContinuesAfterIndividualFailure() async {
    let ids = (0..<3).map { _ in UUID() }
    let recomputer = StubRecomputer()
    recomputer.failureID = ids[1]
    var reads = 0
    let refresher = DerivedDataRefresher(
      pendingIDs: {
        reads += 1
        return ids
      }, recomputer: recomputer, canContinue: { true })
    await refresher.run()
    await refresher.run()
    #expect(reads == 1)
    #expect(recomputer.calls == ids)
  }

  @Test func failedReadEndsAttemptWithoutRetry() async {
    let recomputer = StubRecomputer()
    var reads = 0
    let refresher = DerivedDataRefresher(
      pendingIDs: {
        reads += 1
        throw Failure.injected
      },
      recomputer: recomputer, canContinue: { true })
    await refresher.run()
    await refresher.run()
    #expect(reads == 1)
    #expect(recomputer.calls.isEmpty)
  }

  @Test func ineligibleAttemptDoesNotReadOrRetry() async {
    var reads = 0
    let recomputer = StubRecomputer()
    recomputer.allowed = false
    let refresher = DerivedDataRefresher(
      pendingIDs: {
        reads += 1
        return [UUID()]
      },
      recomputer: recomputer, canContinue: { recomputer.allowed })
    await refresher.run()
    recomputer.allowed = true
    await refresher.run()
    #expect(reads == 0)
    #expect(recomputer.calls.isEmpty)
  }

  @Test func rechecksEligibilityBetweenSessions() async {
    let ids = [UUID(), UUID()]
    let recomputer = StubRecomputer()
    recomputer.onCall = { recomputer.allowed = false }
    let refresher = DerivedDataRefresher(
      pendingIDs: { ids }, recomputer: recomputer, canContinue: { recomputer.allowed })
    await refresher.run()
    #expect(recomputer.calls == [ids[0]])
  }

  @Test(arguments: [false, true])
  func cancellationStopsAfterInFlightSessionAndConcurrentRunDoesNotRepeat(fail: Bool) async {
    let ids = [UUID(), UUID()]
    let gate = TestGate()
    let recomputer = StubRecomputer()
    recomputer.gate = gate
    if fail { recomputer.failureID = ids[0] }
    let refresher = DerivedDataRefresher(
      pendingIDs: { ids }, recomputer: recomputer, canContinue: { true })
    let task = Task { await refresher.run() }
    await gate.waitUntilBlocked()
    await refresher.run()
    task.cancel()
    await gate.release()
    await task.value
    await refresher.run()
    #expect(recomputer.calls == [ids[0]])
  }

  @Test func cancellationBeforeExecutionDoesNotRead() async {
    var reads = 0
    let recomputer = StubRecomputer()
    let refresher = DerivedDataRefresher(
      pendingIDs: {
        reads += 1
        return [UUID()]
      },
      recomputer: recomputer, canContinue: { true })
    let task = Task { await refresher.run() }
    task.cancel()
    await task.value
    #expect(reads == 0)
    #expect(recomputer.calls.isEmpty)
  }

  @Test func cancellationErrorEndsAttempt() async {
    let ids = [UUID(), UUID()]
    let recomputer = StubRecomputer()
    recomputer.cancel = true
    let refresher = DerivedDataRefresher(
      pendingIDs: { ids }, recomputer: recomputer, canContinue: { true })
    await refresher.run()
    #expect(recomputer.calls == [ids[0]])
  }
}

private enum Failure: Error { case injected }

@MainActor
private final class StubRecomputer: DerivedDataRecomputing {
  var allowed = true
  var calls: [UUID] = []
  var failureID: UUID?
  var cancel = false
  var gate: TestGate?
  var onCall: (() -> Void)?

  func recomputeDerivedData(sessionID: UUID) async throws -> Bool {
    calls.append(sessionID)
    if let gate { await gate.suspend() }
    onCall?()
    if cancel { throw CancellationError() }
    if failureID == sessionID { throw Failure.injected }
    return true
  }
}
