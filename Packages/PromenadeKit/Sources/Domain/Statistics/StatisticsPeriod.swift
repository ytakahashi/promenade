import Foundation

public enum StatisticsGranularity: Sendable, CaseIterable {
  case day, week, month, year

  fileprivate var component: Calendar.Component {
    switch self {
    case .day: .day
    case .week: .weekOfYear
    case .month: .month
    case .year: .year
    }
  }

  fileprivate var bucketComponent: Calendar.Component {
    switch self {
    case .day: .hour
    case .week, .month: .day
    case .year: .month
    }
  }
}

public struct StatisticsPeriod: Sendable, Equatable {
  public let granularity: StatisticsGranularity
  public let interval: DateInterval

  /// Returns nil when the calendar cannot place `date`, e.g. far outside its supported range.
  public init?(containing date: Date, granularity: StatisticsGranularity, calendar: Calendar) {
    guard let interval = calendar.dateInterval(of: granularity.component, for: date) else {
      return nil
    }
    self.granularity = granularity
    self.interval = interval
  }

  /// Use the same calendar used to create the period and its entries.
  public func moved(by offset: Int, calendar: Calendar) -> StatisticsPeriod? {
    guard
      let date = calendar.date(byAdding: granularity.component, value: offset, to: interval.start)
    else { return nil }
    return StatisticsPeriod(containing: date, granularity: granularity, calendar: calendar)
  }

  /// Half-open bucket ranges covering the period in order: hours for day, days for week and
  /// month, months for year.
  public func bucketRanges(calendar: Calendar) -> [Range<Date>] {
    var ranges: [Range<Date>] = []
    var start = interval.start
    while start < interval.end {
      // Take each bucket's own calendar interval instead of adding one unit to the previous
      // start: where midnight does not exist on a DST day, the period starts at 01:00 and adding
      // days would shift every later bucket by that hour. This also yields 23 or 25 hours on DST
      // days.
      guard let bucket = calendar.dateInterval(of: granularity.bucketComponent, for: start),
        bucket.end > start
      else { break }
      let end = min(bucket.end, interval.end)
      ranges.append(start..<end)
      start = end
    }
    return ranges
  }
}
