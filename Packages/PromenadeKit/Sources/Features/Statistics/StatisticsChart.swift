import Charts
import Domain
import SwiftUI

struct StatisticsChart: View {
  let statistics: PeriodStatistics
  let calendar: Calendar
  let metric: StatisticsMetric
  let selectedBucketStart: Date?
  let toggleBucket: (Date?) -> Void
  @Environment(\.locale) private var locale

  private var granularity: StatisticsGranularity { statistics.period.granularity }
  private var formatting: StatisticsFormatting {
    StatisticsFormatting(locale: locale, calendar: calendar)
  }
  private var component: Calendar.Component {
    switch granularity {
    case .day: .hour
    case .week, .month: .day
    case .year: .month
    }
  }
  private var selectedBucket: PeriodStatistics.Bucket? {
    selectedBucketStart.flatMap { statistics.bucket(containing: $0) }
  }

  var body: some View {
    Chart {
      ForEach(statistics.buckets, id: \.start) { bucket in
        if let value = metric.value(in: bucket.totals), value > 0 {
          BarMark(
            x: .value("Date", bucket.start, unit: component, calendar: calendar),
            y: .value("Value", chartValue(value))
          )
          .foregroundStyle(Color.accentColor)
          .accessibilityLabel(formatting.bucketTitle(bucket.range, granularity: granularity))
          .accessibilityValue(formatting.selectionValue(bucket.totals, metric: metric))
        }
      }
      if let bucket = selectedBucket {
        RuleMark(x: .value("Selected date", midpoint(bucket.range)))
          .foregroundStyle(.secondary)
          .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart))) {
            VStack(spacing: 2) {
              Text(verbatim: formatting.bucketTitle(bucket.range, granularity: granularity))
                .font(.caption)
              Text(verbatim: formatting.selectionValue(bucket.totals, metric: metric))
                .font(.caption.bold())
                .monospacedDigit()
            }
            .foregroundStyle(Color.primary)
            .padding(8)
            // Unlike the system background colors, it stands out from the card in both appearances.
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
          }
      }
    }
    // Keep the full period visible even when every bucket is empty or unmeasured.
    .chartXScale(domain: statistics.period.interval.start...statistics.period.interval.end)
    .chartYScale(domain: 0...upperBound)
    .chartXAxis {
      if granularity == .month {
        AxisMarks(values: .automatic(desiredCount: 6)) { value in axis(value) }
      } else {
        AxisMarks(values: axisDates) { value in axis(value) }
      }
    }
    .chartYAxisLabel(formatting.chartUnit(metric: metric, granularity: granularity))
    .chartXSelection(value: Binding(get: { selectedBucketStart }, set: { toggleBucket($0) }))
    .chartGesture { proxy in
      // A drag selection competes with the enclosing ScrollView, even after a long press.
      // Tap selection keeps vertical scrolling available from anywhere in the chart.
      SpatialTapGesture()
        .onEnded { proxy.selectXValue(at: $0.location.x) }
    }
    .environment(\.calendar, calendar)
    .environment(\.timeZone, calendar.timeZone)
    .frame(height: 240)
    .padding(.top, 32)
    .accessibilityIdentifier("statistics.chart")
    .accessibilityValue(
      selectedBucket.map {
        let title = formatting.bucketTitle($0.range, granularity: granularity)
        return "\(title), \(formatting.selectionValue($0.totals, metric: metric))"
      } ?? "")
  }

  private var axisDates: [Date] {
    let starts = statistics.buckets.map(\.start)
    switch granularity {
    case .day:
      return starts.filter { [0, 6, 12, 18].contains(calendar.component(.hour, from: $0)) }
    case .week, .month, .year: return starts
    }
  }

  @AxisMarkBuilder
  private func axis(_ value: AxisValue) -> some AxisMark {
    AxisGridLine()
    AxisTick()
    if let date = value.as(Date.self), date < statistics.period.interval.end {
      AxisValueLabel {
        Text(verbatim: formatting.axisLabel(date, granularity: granularity))
      }
    }
  }

  private var upperBound: Double {
    let maximum = statistics.buckets.compactMap { metric.value(in: $0.totals) }.max() ?? 0
    return formatting.chartUpperBound(maximum: maximum, metric: metric, granularity: granularity)
  }

  private func chartValue(_ value: Double) -> Double {
    formatting.chartValue(value, metric: metric, granularity: granularity)
  }

  private func midpoint(_ range: Range<Date>) -> Date {
    range.lowerBound.addingTimeInterval(range.upperBound.timeIntervalSince(range.lowerBound) / 2)
  }
}
