import Domain

/// Keep the displayed summary and the editable source from the same completed read.
nonisolated struct SessionSummaryData: Sendable {
  let record: SessionRecord
  let summary: SessionSummary

  /// Raw points rather than the summary's route: rejected points are still valid end positions.
  var hasRecordedPoints: Bool { record.segments.contains { !$0.points.isEmpty } }

  init?(record: SessionRecord, route: RouteFilter.Configuration) {
    guard let summary = SessionSummary(record: record, route: route) else { return nil }
    self.record = record
    self.summary = summary
  }
}
