import Domain
import SwiftUI

struct AllTimeCard: View {
  let totals: MetricTotals
  @Environment(\.locale) private var locale

  var body: some View {
    let formatting = MetricFormatting(locale: locale)
    VStack(alignment: .leading, spacing: 16) {
      Text("All Time", bundle: .module)
        .font(.headline)
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 16) { metrics(formatting) }
        VStack(alignment: .leading, spacing: 16) { metrics(formatting) }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
  }

  @ViewBuilder
  private func metrics(_ formatting: MetricFormatting) -> some View {
    metric(Text("Distance", bundle: .module), value: formatting.distance(totals.distance))
    metric(Text("Steps", bundle: .module), value: formatting.steps(totals.steps))
    metric(
      Text("Walking Time", bundle: .module),
      value: formatting.aggregateDuration(totals.walkingDuration))
  }

  private func metric(_ title: Text, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      title.font(.caption).foregroundStyle(.secondary)
      Text(verbatim: value).font(.headline).monospacedDigit()
    }
    .accessibilityElement(children: .combine)
  }
}
