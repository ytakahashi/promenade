import Foundation

/// The walking speed over one interval of a session.
public struct SpeedSample: Sendable, Equatable {
  public let start: Date
  /// Meters per second; nil when segments cover too little of this interval to tell.
  public let speed: Double?

  public init(start: Date, speed: Double?) {
    self.start = start
    self.speed = speed
  }
}

/// Splits a finished session into fixed intervals of walking speed.
public enum WalkSpeedSeries {
  /// Display only and never stored, so changing it does not require bumping `DerivedDataVersion`.
  public static let defaultInterval: TimeInterval = 60

  /// The smallest share of an interval that segments must cover for it to have a speed.
  ///
  /// `RouteFilter` adds distance in lumps, so an interval that a segment barely reaches reads as a
  /// spike or as a false drop, depending on whether a lump lands in it. Such an interval always
  /// borders a gap or the session's end, so leaving it empty only widens a break in the line.
  private static let minimumCoverageRatio = 0.25

  /// Samples from the session start to its end, or empty for an unfinished or zero-length session.
  ///
  /// Distance comes from `RouteFilter`, as elsewhere on screen: the increments of
  /// `Accumulator.distance` rather than distances between points, so an anchor reset's jump is not
  /// counted. Time outside segments, including signal gaps, has no points and is not divided by.
  public static func samples(
    for record: SessionRecord, filter: RouteFilter, interval: TimeInterval
  ) -> [SpeedSample] {
    precondition(interval > 0, "The interval must be positive")
    guard record.state == .finished, let end = record.endDate else { return [] }
    let duration = end.timeIntervalSince(record.startDate)
    guard duration > 0 else { return [] }

    let count = Int((duration / interval).rounded(.up))
    var distances = [Double](repeating: 0, count: count)
    var coverages = [TimeInterval](repeating: 0, count: count)

    for segment in record.segments {
      guard let segmentEnd = segment.endDate else { continue }
      let lower = max(segment.startDate.timeIntervalSince(record.startDate), 0)
      let upper = min(segmentEnd.timeIntervalSince(record.startDate), duration)
      guard upper > lower else { continue }

      let first = Int(lower / interval)
      let last = Int((upper / interval).rounded(.up)) - 1
      for index in first...last {
        let intervalStart = Double(index) * interval
        coverages[index] += min(upper, intervalStart + interval) - max(lower, intervalStart)
      }

      var accumulator = filter.makeAccumulator()
      for point in segment.points {
        let previous = accumulator.distance
        accumulator.add(point)
        // A point exactly at the segment's end falls on the next interval's start, which this
        // segment does not cover. Clamping keeps its distance in a covered interval.
        let index = Int(point.timestamp.timeIntervalSince(record.startDate) / interval)
        distances[min(max(index, first), last)] += accumulator.distance - previous
      }
    }

    let minimumCoverage = interval * minimumCoverageRatio
    return (0..<count).map { index in
      SpeedSample(
        start: record.startDate.addingTimeInterval(Double(index) * interval),
        speed: coverages[index] >= minimumCoverage ? distances[index] / coverages[index] : nil
      )
    }
  }
}
