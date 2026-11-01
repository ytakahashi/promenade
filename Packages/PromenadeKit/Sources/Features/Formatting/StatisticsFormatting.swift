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

  func chartValue(_ value: Double, metric: StatisticsMetric, granularity: StatisticsGranularity)
    -> Double
  {
    switch metric {
    case .distance: value / MetricFormatting(locale: locale).distanceUnit.meters
    case .steps: value
    case .duration: value / (granularity == .year ? 3600 : 60)
    }
  }

  /// The top of the Y axis for the largest bucket value, in chart units.
  func chartUpperBound(
    maximum: Double, metric: StatisticsMetric, granularity: StatisticsGranularity
  ) -> Double {
    // A floor keeps empty and very small periods from getting ticks such as 0.2 steps.
    let floor: Double =
      switch metric {
      case .distance: 1
      case .steps: 10
      case .duration: granularity == .year ? 1 : 10
      }
    return max(chartValue(maximum, metric: metric, granularity: granularity) * 1.1, floor)
  }

  func chartUnit(metric: StatisticsMetric, granularity: StatisticsGranularity) -> String {
    switch metric {
    case .distance: MetricFormatting(locale: locale).distanceUnit == .kilometers ? "km" : "mi"
    case .steps: String(localized: "Steps", bundle: .module)
    case .duration: granularity == .year ? "h" : "min"
    }
  }

  func axisLabel(_ date: Date, granularity: StatisticsGranularity) -> String {
    switch granularity {
    case .day: calendar.component(.hour, from: date).formatted(.number.locale(locale))
    case .week: date.formatted(style.weekday(.abbreviated))
    case .month: date.formatted(style.day())
    case .year: date.formatted(style.month(.narrow))
    }
  }

  func bucketTitle(_ range: Range<Date>, granularity: StatisticsGranularity) -> String {
    switch granularity {
    // Only the start: an hour interval ending at midnight would be formatted with both full dates.
    case .day: return range.lowerBound.formatted(style.hour().minute())
    case .week, .month: return range.lowerBound.formatted(style.month(.abbreviated).day())
    case .year: return range.lowerBound.formatted(style.month(.wide).year())
    }
  }

  func selectionValue(_ totals: MetricTotals, metric: StatisticsMetric) -> String {
    if metric == .steps, let steps = totals.steps {
      return String(localized: "\(steps) steps", bundle: .module, locale: locale)
    }
    return value(metric.value(in: totals), metric: metric)
  }
}
