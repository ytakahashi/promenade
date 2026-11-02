import Foundation

/// The end positions a session can be trimmed to, with the distance kept by each.
///
/// Built once per session so that moving the end position does not filter every point again. The
/// walking time of a candidate comes from `SessionMetricsCalculator.timing(segments:sessionStart:asOf:)`.
public struct TrimTimeline: Sendable {
  /// Every recorded point's time, strictly ascending. These are the selectable end positions.
  public let dates: [Date]
  /// Filtered distance up to each date. Same index as `dates`.
  public let distances: [Double]

  /// Folds the points in the same order as `SessionMetricsCalculator.metrics(for:filter:asOf:)`,
  /// so each distance equals the one computed from `SessionRecord.trimmed(endingAt:)`.
  public init(record: SessionRecord, filter: RouteFilter) {
    var dates: [Date] = []
    var distances: [Double] = []
    var completedSegmentsDistance = 0.0
    for segment in record.segments {
      var accumulator = filter.makeAccumulator()
      for point in segment.points {
        accumulator.add(point)
        // A segment may start at its predecessor's last point time. That first point adds no
        // distance, so the existing candidate already holds the right value.
        guard dates.last != point.timestamp else { continue }
        dates.append(point.timestamp)
        distances.append(completedSegmentsDistance + accumulator.distance)
      }
      completedSegmentsDistance += accumulator.distance
    }
    self.dates = dates
    self.distances = distances
  }

  /// The latest recorded point at or before `date`, so gaps snap to the point preceding them.
  public func candidate(atOrBefore date: Date) -> Int? {
    var low = 0
    var high = dates.count
    while low < high {
      let middle = (low + high) / 2
      if dates[middle] <= date {
        low = middle + 1
      } else {
        high = middle
      }
    }
    return low > 0 ? low - 1 : nil
  }
}
