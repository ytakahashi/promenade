import Domain
import SwiftUI

struct StatisticsSummaryCard: View {
  let statistics: PeriodStatistics
  let calendar: Calendar
  let metric: StatisticsMetric
  let setMetric: (StatisticsMetric) -> Void
  let selectedBucketStart: Date?
  let toggleBucket: (Date?) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    let formatting = StatisticsFormatting(locale: locale, calendar: calendar)
    VStack(alignment: .leading, spacing: 12) {
      Picker(selection: Binding(get: { metric }, set: { setMetric($0) })) {
        ForEach(StatisticsMetric.allCases, id: \.self) { metric in
          metric.title.tag(metric)
        }
      } label: {
        Text("Metric", bundle: .module)
      }
      .pickerStyle(.segmented)
      Text("Total", bundle: .module)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Text(verbatim: formatting.value(metric.value(in: statistics.totals), metric: metric))
        .font(.largeTitle.bold())
        .monospacedDigit()
      if statistics.period.granularity != .day {
        let daily = formatting.value(metric.value(in: statistics.dailyAverage), metric: metric)
        let perWalk = formatting.value(
          metric.value(in: statistics.perSessionAverage), metric: metric)
        ViewThatFits(in: .horizontal) {
          HStack {
            Text("\(daily) / day", bundle: .module)
            Text(verbatim: "·").accessibilityHidden(true)
            Text("\(perWalk) / walk", bundle: .module)
          }
          .accessibilityElement(children: .combine)
          VStack(alignment: .leading) {
            Text("\(daily) / day", bundle: .module)
            Text("\(perWalk) / walk", bundle: .module)
          }
          .accessibilityElement(children: .combine)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
      HStack {
        if statistics.period.granularity != .day {
          Text("\(statistics.walkedDays) days", bundle: .module)
          Text(verbatim: "·").accessibilityHidden(true)
        }
        Text("\(statistics.totals.sessionCount) walks", bundle: .module)
      }
      .accessibilityElement(children: .combine)
      .font(.subheadline)
      .foregroundStyle(.secondary)
      StatisticsChart(
        statistics: statistics, calendar: calendar, metric: metric,
        selectedBucketStart: selectedBucketStart, toggleBucket: toggleBucket)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
  }
}
