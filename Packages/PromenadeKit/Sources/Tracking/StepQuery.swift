import Foundation
import Sensors

/// A bounded historical step query, independent of recording state.
@MainActor
public struct StepQuery {
  private let pedometer: any PedometerProvider
  private let timeout: TimeInterval
  private let sleep: @Sendable (TimeInterval) async throws -> Void

  public init(
    pedometer: any PedometerProvider, timeout: TimeInterval,
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
      try await Task.sleep(for: .seconds($0))
    }
  ) {
    self.pedometer = pedometer
    self.timeout = timeout
    self.sleep = sleep
  }

  /// Returns nil on timeout or measurement failure; cancellation throws `CancellationError`.
  ///
  /// Cancellation ends the wait without waiting for the provider to respond or the timeout to
  /// elapse. Results arriving after completion are ignored.
  public func steps(from start: Date, to end: Date) async throws -> Int? {
    try Task.checkCancellation()
    let pedometer = pedometer
    let sleep = sleep
    let timeout = timeout
    let outcome = StepQueryOutcome()
    let steps = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        outcome.continuation = continuation
        // Unstructured so the wait can end without awaiting a query that ignores cancellation.
        outcome.timer = Task {
          do { try await sleep(timeout) } catch { return }
          trackingLogger.warning("Step query timed out")
          outcome.resume(nil)
        }
        outcome.query = Task { outcome.resume(await pedometer.steps(from: start, to: end)) }
      }
    } onCancel: {
      // Hop to the main actor: cancellation may run before the continuation has been stored.
      // The operation runs synchronously on the main actor until it suspends, so this enqueued
      // resume always finds it.
      Task { @MainActor in outcome.resume(nil) }
    }
    try Task.checkCancellation()
    return steps
  }
}

/// Resumes the waiting continuation once, with the query result or `nil` on timeout or
/// cancellation.
@MainActor
private final class StepQueryOutcome {
  var continuation: CheckedContinuation<Int?, Never>?
  var timer: Task<Void, Never>?
  var query: Task<Void, Never>?

  func resume(_ steps: Int?) {
    guard let continuation else { return }
    self.continuation = nil
    timer?.cancel()
    timer = nil
    query?.cancel()
    query = nil
    continuation.resume(returning: steps)
  }
}
