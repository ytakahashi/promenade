import Domain
import Foundation
import Sensors

// Step counting: closing queries and the live subscription of the open segment.
extension TrackingEngine {
  /// Steps of the open segment up to `date`, or `nil` without an open segment.
  ///
  /// Queried before every store call that closes the segment, so the closure and its steps are
  /// saved together. A retried transition queries again rather than reusing a cached value.
  /// Throws `CancellationError` when the operation is cancelled, before anything is saved.
  func closingSteps(until date: Date) async throws -> Int? {
    guard let segment = liveSession?.record.segments.last, segment.endDate == nil else {
      return nil
    }
    return try await steps(from: segment.startDate, to: date)
  }

  /// Queries closed segments whose steps could not be measured when they closed, by segment index.
  ///
  /// One unmeasured segment leaves the session total unmeasured, so it stops at the first failure:
  /// further queries could not change the total, and each could delay the finish by a timeout.
  func recoveredSteps(of record: SessionRecord) async throws -> [Int: Int] {
    var recovered: [Int: Int] = [:]
    for segment in record.unmeasuredSegments {
      guard let steps = try await steps(from: segment.start, to: segment.end) else { break }
      recovered[segment.index] = steps
    }
    return recovered
  }

  /// Bounded by `configuration.stepQueryTimeout`; a slow or failed query saves unmeasured steps
  /// instead of delaying the transition.
  ///
  /// Cancellation ends the wait immediately and throws, so a cancelled operation (e.g. launch
  /// recovery) releases its resources without waiting for the query or the timeout, and does not
  /// go on to save.
  func steps(from start: Date, to end: Date) async throws -> Int? {
    try Task.checkCancellation()
    let pedometer = pedometer
    let sleep = sleep
    let timeout = configuration.stepQueryTimeout
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
      // Hops to the main actor rather than resuming directly, as in `completes(_:within:)`: for an
      // already-cancelled task `onCancel` runs before the operation has stored the continuation.
      // The operation runs synchronously on the main actor until it suspends, so this enqueued
      // resume always finds it.
      Task { @MainActor in outcome.resume(nil) }
    }
    try Task.checkCancellation()
    return steps
  }

  /// Subscribes to live steps from the open segment's start while recording, and stops otherwise.
  ///
  /// Call after any operation that can open, close or discard a segment. Restarts only when the
  /// open segment changed, so calling it repeatedly is harmless.
  func syncLiveSteps() {
    let open: Date? =
      if case .recording = phase, let last = liveSession?.record.segments.last,
        last.endDate == nil
      {
        last.startDate
      } else {
        nil
      }
    guard open != liveStepsSegmentStart else { return }
    liveStepsTask?.cancel()
    liveStepsTask = nil
    liveStepsSegmentStart = open
    guard let open else { return }
    let pedometer = pedometer
    liveStepsTask = Task { [weak self] in
      for await steps in pedometer.liveSteps(from: open) {
        guard !Task.isCancelled else { return }
        self?.liveSession?.updateOpenSegmentSteps(steps, segmentStart: open)
      }
    }
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
