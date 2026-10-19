import Foundation

public enum SessionMetricsCalculator {
  /// Computes time components for nonoverlapping segments sorted by index.
  /// `asOf` is the session end date, or the current time for a live session.
  public static func timing(
    segments: [SegmentRecord],
    sessionStart: Date,
    asOf: Date
  ) -> SessionTiming {
    let elapsed = max(0, asOf.timeIntervalSince(sessionStart))
    var pause: TimeInterval = 0
    var interruption: TimeInterval = 0

    for (index, segment) in segments.enumerated() {
      guard let end = segment.endDate else { continue }
      let nextStart = index + 1 < segments.count ? segments[index + 1].startDate : asOf
      // Live calculations may end inside a gap. Count only the part inside the session window.
      let gap = max(0, min(nextStart, asOf).timeIntervalSince(max(end, sessionStart)))
      switch segment.endReason {
      case .paused:
        pause += gap
      case .interrupted:
        interruption += gap
      case .signalGap, .finished, nil:
        break
      }
    }

    // A signal gap is still walking time, so summing segment lengths would undercount it.
    return SessionTiming(
      elapsed: elapsed,
      walking: max(0, elapsed - pause - interruption),
      pause: pause,
      interruption: interruption
    )
  }

  /// Uses all recorded points; `asOf` controls time calculations, not historical route playback.
  /// A finished session always uses its saved end date so its metrics remain stable.
  public static func metrics(
    for session: SessionRecord,
    filter: RouteFilter,
    asOf: Date
  ) -> SessionMetrics {
    let end = session.endDate ?? asOf
    let timing = timing(segments: session.segments, sessionStart: session.startDate, asOf: end)
    // Each segment gets a fresh accumulator: gaps must never contribute route distance.
    let distance = session.segments.reduce(0.0) { $0 + filter.filter($1.points).distance }
    let measuredSteps = session.segments.compactMap(\.steps)
    let steps =
      !session.segments.isEmpty && measuredSteps.count == session.segments.count
      ? measuredSteps.reduce(0, +) : nil
    return SessionMetrics(distance: distance, timing: timing, steps: steps)
  }
}
