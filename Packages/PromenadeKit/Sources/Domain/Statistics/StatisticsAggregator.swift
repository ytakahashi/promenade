import Foundation

public enum StatisticsAggregator {
  /// Periods and entries must be constructed with the same calendar used for aggregation.
  public static func statistics(
    for period: StatisticsPeriod, entries: [StatisticsEntry], calendar: Calendar
  ) -> PeriodStatistics {
    let ranges = period.bucketRanges(calendar: calendar)
    var bucketTotals = Array(repeating: MetricTotals.zero, count: ranges.count)
    var totals = MetricTotals.zero
    var walkedDays: Set<Date> = []
    var stepMeasuredDays: Set<Date> = []
    var included: [StatisticsEntry] = []
    for entry in entries {
      // Bucket ranges cover the period contiguously, so this also filters to the period. An entry
      // outside every bucket is only possible if the calendar fails to enumerate them; it is left
      // out of the totals so that totals always equal the sum of the buckets.
      guard let index = ranges.firstIndex(where: { $0.contains(entry.localStart) }) else {
        continue
      }
      bucketTotals[index].add(entry)
      totals.add(entry)
      // Count days separately from buckets: a year has month buckets, not day buckets.
      let day = calendar.startOfDay(for: entry.localStart)
      walkedDays.insert(day)
      if entry.steps != nil { stepMeasuredDays.insert(day) }
      included.append(entry)
    }
    included.sort {
      if $0.localStart == $1.localStart { return $0.id.uuidString < $1.id.uuidString }
      return $0.localStart < $1.localStart
    }
    return PeriodStatistics(
      period: period,
      buckets: ranges.indices.map { .init(range: ranges[$0], totals: bucketTotals[$0]) },
      totals: totals, walkedDays: walkedDays.count, stepMeasuredDays: stepMeasuredDays.count,
      entries: included
    )
  }

  public static func allTime(_ entries: [StatisticsEntry]) -> MetricTotals {
    entries.reduce(into: .zero) { $0.add($1) }
  }
}
