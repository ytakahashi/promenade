import Domain
import SwiftUI

struct HistoryRow: View {
  let item: SessionListItem
  @Environment(\.locale) private var locale

  var body: some View {
    let formatting = MetricFormatting(locale: locale)
    let timeZone = TimeZone(identifier: item.timeZoneIdentifier) ?? .current
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: formatting.dateTime(item.startDate, in: timeZone))
        .font(.headline)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) { metrics(formatting) }
        VStack(alignment: .leading, spacing: 2) { metrics(formatting) }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .monospacedDigit()
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func metrics(_ formatting: MetricFormatting) -> some View {
    Label {
      Text(verbatim: formatting.distance(item.distance))
    } icon: {
      Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
    }
    .accessibilityLabel(Text("Distance", bundle: .module))
    .accessibilityValue(formatting.distance(item.distance, width: .wide))
    Label {
      Text(verbatim: formatting.duration(item.walkingDuration))
    } icon: {
      Image(systemName: "clock")
    }
    .accessibilityLabel(Text("Walking time", bundle: .module))
    .accessibilityValue(formatting.durationAccessibility(item.walkingDuration))
    Label {
      Text(verbatim: formatting.steps(item.steps))
    } icon: {
      Image(systemName: "shoeprints.fill")
    }
    .accessibilityLabel(Text("Steps", bundle: .module))
    .accessibilityValue(formatting.stepsAccessibility(item.steps))
  }
}
