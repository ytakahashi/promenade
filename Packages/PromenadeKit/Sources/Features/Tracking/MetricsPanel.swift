import Domain
import SwiftUI

struct MetricsPanel: View {
  let metrics: SessionMetrics
  @Environment(\.locale) private var locale

  var body: some View {
    let formatting = MetricFormatting(locale: locale)
    VStack(alignment: .leading, spacing: 20) {
      metric(
        "Walking time", value: formatting.duration(metrics.timing.walking),
        accessibility: formatting.durationAccessibility(metrics.timing.walking), font: .largeTitle)
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 24) { secondaryMetrics(formatting) }
          .fixedSize(horizontal: true, vertical: false)
        VStack(alignment: .leading, spacing: 16) { secondaryMetrics(formatting) }
      }
    }
    .monospacedDigit()
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial)
  }

  @ViewBuilder
  private func secondaryMetrics(_ formatting: MetricFormatting) -> some View {
    metric(
      "Rest time", value: formatting.duration(metrics.timing.pause),
      accessibility: formatting.durationAccessibility(metrics.timing.pause))
    metric(
      "Distance", value: formatting.distance(metrics.distance),
      accessibility: formatting.distance(metrics.distance, width: .wide))
    metric(
      "Steps", value: formatting.steps(metrics.steps),
      accessibility: formatting.stepsAccessibility(metrics.steps))
    metric(
      "Average pace",
      value: formatting.pace(secondsPerMeter: metrics.averagePace, distance: metrics.distance),
      accessibility: formatting.paceAccessibility(
        secondsPerMeter: metrics.averagePace, distance: metrics.distance))
  }

  private func metric(
    _ label: LocalizedStringKey, value: String, accessibility: String, font: Font = .title3
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label, bundle: .module)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Text(value).font(font).fontWeight(.semibold)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(label, bundle: .module))
    .accessibilityValue(accessibility)
  }
}

#Preview("Metric") {
  MetricsPanel(
    metrics: SessionMetrics(
      distance: 2540,
      timing: SessionTiming(elapsed: 2100, walking: 1800, pause: 300, interruption: 0),
      steps: 3240)
  )
  .environment(\.locale, Locale(identifier: "en_GB@measure=metric"))
}

#Preview("Long walk, large text") {
  ScrollView {
    MetricsPanel(
      metrics: SessionMetrics(
        distance: 120_000,
        timing: SessionTiming(elapsed: 94_000, walking: 90_000, pause: 4000, interruption: 0),
        steps: 165_432))
  }
  .environment(\.locale, Locale(identifier: "en_US"))
  .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("No distance") {
  MetricsPanel(
    metrics: SessionMetrics(
      distance: 0, timing: SessionTiming(elapsed: 0, walking: 0, pause: 0, interruption: 0),
      steps: nil))
}
