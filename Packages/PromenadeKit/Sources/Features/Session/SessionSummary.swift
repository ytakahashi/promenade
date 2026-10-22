import Domain
import Foundation

/// A finished walk as shown after Finish, built from the saved record rather than live state.
struct SessionSummary {
  let id: UUID
  let map: TrackingMapContent
  let metrics: SessionMetrics
  let startDate: Date
  let endDate: Date
  /// The zone the walk was recorded in, or the device's when the saved identifier is invalid.
  let timeZone: TimeZone

  /// Returns nil for an unfinished record: its metrics would not be final yet.
  init?(record: SessionRecord, route: RouteFilter.Configuration) {
    guard record.state == .finished, let endDate = record.endDate else { return nil }
    let filter = RouteFilter(configuration: route)
    id = record.id
    map = TrackingMapContent(segments: record.segments.map { filter.filter($0.points) })
    // The calculator is the single definition of saved-walk metrics; filtering again here keeps
    // the summary consistent with it at a one-off cost.
    metrics = SessionMetricsCalculator.metrics(for: record, filter: filter, asOf: endDate)
    startDate = record.startDate
    self.endDate = endDate
    timeZone = TimeZone(identifier: record.timeZoneIdentifier) ?? .current
  }
}
