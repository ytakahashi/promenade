import Foundation
import Sensors
import Synchronization
import Testing

@testable import Tracking

@MainActor
struct StepQueryTests {
  @Test(arguments: [Optional(42), nil])
  func returnsProviderResult(steps: Int?) async throws {
    let provider = DeferredStepPedometer()
    let query = makeQuery(provider)
    let task = Task { try await query.steps(from: date(10), to: date(20)) }
    await eventually { provider.ranges.count == 1 }
    #expect(provider.ranges == [date(10)...date(20)])
    provider.complete(at: 0, with: steps)
    #expect(try await task.value == steps)
  }

  @Test func timeoutDoesNotWaitForUncooperativeProvider() async throws {
    let provider = DeferredStepPedometer()
    let timer = TestGate()
    let query = StepQuery(
      pedometer: provider, timeout: 2,
      sleep: { seconds in
        #expect(seconds == 2)
        await timer.suspend()
      })
    let task = Task { try await query.steps(from: date(0), to: date(10)) }
    await eventually { provider.ranges.count == 1 }
    await timer.waitUntilBlocked()
    await timer.release()
    #expect(try await task.value == nil)
    // The query ignores cancellation and finishes after the caller has already returned.
    provider.complete(at: 0, with: 100)
  }

  @Test func cancellationEndsWaitAndLateResultIsIgnored() async throws {
    let provider = DeferredStepPedometer()
    let query = makeQuery(provider)
    let task = Task { try await query.steps(from: date(0), to: date(10)) }
    await eventually { provider.ranges.count == 1 }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    provider.complete(at: 0, with: 100)
  }

  @Test func cancellationBeforeStartingDoesNotQuery() async {
    let provider = DeferredStepPedometer()
    let query = makeQuery(provider)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await query.steps(from: date(0), to: date(10))
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(provider.ranges.isEmpty)
  }

  @Test func concurrentQueriesHaveIndependentOutcomes() async throws {
    let provider = DeferredStepPedometer()
    let query = makeQuery(provider)
    let first = Task { try await query.steps(from: date(0), to: date(10)) }
    await eventually { provider.ranges.count == 1 }
    let second = Task { try await query.steps(from: date(20), to: date(30)) }
    await eventually { provider.ranges.count == 2 }
    first.cancel()
    await #expect(throws: CancellationError.self) { try await first.value }
    provider.complete(at: 1, with: 20)
    #expect(try await second.value == 20)
    provider.complete(at: 0, with: 10)
  }

  private func makeQuery(_ provider: DeferredStepPedometer) -> StepQuery {
    StepQuery(
      pedometer: provider, timeout: 2,
      sleep: { _ in
        try await Task.sleep(for: .seconds(3600))
      })
  }
}

/// Keeps queries suspended even after cancellation to exercise late provider callbacks.
private final class DeferredStepPedometer: PedometerProvider, Sendable {
  private struct State {
    var ranges: [ClosedRange<Date>] = []
    var continuations: [CheckedContinuation<Int?, Never>?] = []
  }
  private let state = Mutex(State())
  var access: MotionAccess { .allowed }
  var ranges: [ClosedRange<Date>] { state.withLock { $0.ranges } }

  func steps(from start: Date, to end: Date) async -> Int? {
    await withCheckedContinuation { continuation in
      state.withLock {
        $0.ranges.append(start...end)
        $0.continuations.append(continuation)
      }
    }
  }

  func complete(at index: Int, with steps: Int?) {
    let continuation = state.withLock {
      let continuation = $0.continuations[index]
      $0.continuations[index] = nil
      return continuation
    }
    continuation?.resume(returning: steps)
  }

  func liveSteps(from start: Date) -> AsyncStream<Int> {
    AsyncStream { $0.finish() }
  }
}
