import Domain
import SwiftUI

/// The saved walk's route and metrics, shared by the post-walk summary and History details.
struct SessionSummaryContent: View {
  let summary: SessionSummary
  @Environment(\.locale) private var locale

  var body: some View {
    let formatting = MetricFormatting(locale: locale)
    let metrics = summary.metrics
    List {
      Section {
        RouteMapView(content: summary.map, camera: .fitsRoute, endpoints: summary.endpoints)
          .frame(height: 260)
          .overlay {
            if summary.map.segments.isEmpty {
              Text("No route was recorded.", bundle: .module)
                .font(.subheadline)
                .padding(8)
                .background(.regularMaterial, in: Capsule())
            }
          }
          .listRowInsets(EdgeInsets())
          .accessibilityIdentifier("summary.map")
      }
      Section {
        row("Distance", formatting.distance(metrics.distance))
        row(
          "Steps", formatting.steps(metrics.steps),
          accessibility: formatting.stepsAccessibility(metrics.steps))
        row(
          "Walking time", formatting.duration(metrics.timing.walking),
          accessibility: formatting.durationAccessibility(metrics.timing.walking))
        row(
          "Rest time", formatting.duration(metrics.timing.pause),
          accessibility: formatting.durationAccessibility(metrics.timing.pause))
        row(
          "Interrupted time", formatting.duration(metrics.timing.interruption),
          accessibility: formatting.durationAccessibility(metrics.timing.interruption))
        row(
          "Average speed",
          formatting.speed(metersPerSecond: metrics.averageSpeed, distance: metrics.distance),
          accessibility: formatting.speedAccessibility(
            metersPerSecond: metrics.averageSpeed, distance: metrics.distance))
        row(
          "Average pace",
          formatting.pace(secondsPerMeter: metrics.averagePace, distance: metrics.distance),
          accessibility: formatting.paceAccessibility(
            secondsPerMeter: metrics.averagePace, distance: metrics.distance))
      }
      Section {
        row("Started", formatting.dateTime(summary.startDate, in: summary.timeZone))
        row("Finished", formatting.dateTime(summary.endDate, in: summary.timeZone))
      }
    }
    .monospacedDigit()
  }

  private func row(_ label: LocalizedStringKey, _ value: String, accessibility: String? = nil)
    -> some View
  {
    LabeledContent {
      Text(verbatim: value)
    } label: {
      Text(label, bundle: .module)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(label, bundle: .module))
    .accessibilityValue(accessibility ?? value)
  }
}
