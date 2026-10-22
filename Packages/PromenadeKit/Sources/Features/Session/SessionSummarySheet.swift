import Domain
import SwiftUI

/// Identifies the walk whose summary sheet is shown.
struct SummaryItem: Identifiable, Equatable {
  let id: UUID
}

struct SessionSummarySheet: View {
  @State private var model: SessionSummaryModel
  let close: () -> Void

  init(model: SessionSummaryModel, close: @escaping () -> Void) {
    _model = State(initialValue: model)
    self.close = close
  }

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(Text("Walk Summary", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button(action: close) { Text("Done", bundle: .module) }
          }
        }
    }
    .onAppear { model.load() }
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      ProgressView()
    case .loaded(let summary):
      SessionSummaryContent(summary: summary)
    case .failed(let failure):
      ContentUnavailableView {
        Label {
          title(failure)
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
      } description: {
        Text("The walk is saved. Retry to read it again.", bundle: .module)
      } actions: {
        Button {
          model.load()
        } label: {
          Text("Retry", bundle: .module)
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  private func title(_ failure: SessionSummaryModel.Failure) -> Text {
    switch failure {
    case .missing: Text("Walk Not Found", bundle: .module)
    case .unfinished: Text("Walk Is Still Being Saved", bundle: .module)
    case .readFailed: Text("Unable to Read Walk", bundle: .module)
    }
  }
}

private struct SessionSummaryContent: View {
  let summary: SessionSummary
  @Environment(\.locale) private var locale

  var body: some View {
    let formatting = MetricFormatting(locale: locale)
    let metrics = summary.metrics
    List {
      Section {
        RouteMapView(content: summary.map, camera: .fitsRoute)
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

#if DEBUG
  #Preview("Loaded") {
    SessionSummarySheet(
      model: SessionSummaryModel(
        sessionID: UUID(), route: .default, read: { _ in .previewFinished(pointCount: 600) }),
      close: {})
  }

  #Preview("No route, other time zone") {
    SessionSummarySheet(
      model: SessionSummaryModel(
        sessionID: UUID(), route: .default,
        read: { _ in .previewFinished(pointCount: 0, timeZone: "America/New_York") }),
      close: {})
  }

  #Preview("Read failure") {
    SessionSummarySheet(
      model: SessionSummaryModel(
        sessionID: UUID(), route: .default, read: { _ in throw CocoaError(.fileReadUnknown) }),
      close: {})
  }

  #Preview("Long walk, large text") {
    SessionSummarySheet(
      model: SessionSummaryModel(
        sessionID: UUID(), route: .default,
        read: { _ in .previewFinished(pointCount: 3600, pause: 4000) }),
      close: {}
    )
    .environment(\.dynamicTypeSize, .accessibility5)
  }

  extension SessionRecord {
    static func previewFinished(
      pointCount: Int, pause: TimeInterval = 300, timeZone: String = TimeZone.current.identifier
    ) -> SessionRecord {
      let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
      let walk = TimeInterval(max(pointCount, 1))
      let points = (0..<pointCount).map { index in
        TrackPoint(
          timestamp: start.addingTimeInterval(Double(index)),
          coordinate: Coordinate(
            latitude: 35.68 + Double(index) * 0.000015,
            longitude: 139.75 + sin(Double(index) * 0.02) * 0.003),
          horizontalAccuracy: 5, altitude: 0, verticalAccuracy: -1, speed: -1, speedAccuracy: -1,
          course: -1)
      }
      let half = points.count / 2
      let resume = start.addingTimeInterval(walk / 2 + pause)
      return SessionRecord(
        id: UUID(), startDate: start, endDate: resume.addingTimeInterval(walk / 2),
        state: .finished, timeZoneIdentifier: timeZone,
        segments: [
          SegmentRecord(
            index: 0, startDate: start, endDate: start.addingTimeInterval(walk / 2),
            endReason: .paused, points: Array(points[..<half])),
          SegmentRecord(
            index: 1, startDate: resume, endDate: resume.addingTimeInterval(walk / 2),
            endReason: .finished,
            points: points[half...].map {
              var point = $0
              point.timestamp.addTimeInterval(pause)
              return point
            }),
        ])
    }
  }
#endif
