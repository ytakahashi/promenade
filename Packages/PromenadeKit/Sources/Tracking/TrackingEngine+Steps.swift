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
  /// instead of delaying the transition indefinitely. Cancellation throws before saving.
  func steps(from start: Date, to end: Date) async throws -> Int? {
    try await stepQuery.steps(from: start, to: end)
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
