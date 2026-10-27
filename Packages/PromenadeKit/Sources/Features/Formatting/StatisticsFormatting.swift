import Domain
import Foundation

struct StatisticsFormatting {
  let locale: Locale
  let calendar: Calendar

  func title(for period: StatisticsPeriod) -> String {
    let start = period.interval.start
    switch period.granularity {
    case .day:
      return start.formatted(style.weekday(.abbreviated).month(.abbreviated).day().year())
    case .week:
      // The interval is half-open; its final instant belongs to the displayed last day.
      let end = period.interval.end.addingTimeInterval(-1)
      return Date.IntervalFormatStyle(
        locale: locale,
        calendar: calendar, timeZone: calendar.timeZone
      ).year().month(.abbreviated).day().format(start..<end)
    case .month:
      return start.formatted(style.month(.wide).year())
    case .year:
      return start.formatted(style.year())
    }
  }

  func value(_ value: Double?, metric: StatisticsMetric) -> String {
    guard let value, value.isFinite, value >= 0 else { return "--" }
    let formatting = MetricFormatting(locale: locale)
    switch metric {
    case .distance: return formatting.distance(value)
    case .steps:
      return value.rounded().formatted(.number.precision(.fractionLength(0)).locale(locale))
    case .duration: return formatting.aggregateDuration(value)
    }
  }

  private var style: Date.FormatStyle {
    Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
  }
}
