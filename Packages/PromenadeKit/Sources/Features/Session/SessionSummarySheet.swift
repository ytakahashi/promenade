import Domain
import SwiftUI

/// Identifies the walk whose summary sheet is shown.
struct SummaryItem: Identifiable, Equatable {
  let id: UUID
}

struct SessionSummarySheet: View {
  @State private var model: SessionSummaryModel
  let close: () -> Void
  let trim: SessionTrimDependencies?

  init(
    model: SessionSummaryModel, trim: SessionTrimDependencies? = nil, close: @escaping () -> Void
  ) {
    self.trim = trim
    _model = State(initialValue: model)
    self.close = close
  }

  var body: some View {
    NavigationStack {
      SessionSummaryView(model: model, trim: trim)
        .navigationTitle(Text("Walk Summary", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button(action: close) { Text("Done", bundle: .module) }
          }
        }
    }
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
