import CoreLocation
import Domain
import Foundation
import MapKit

/// Prepared once for editing: candidates, complete route geometry, and the original speed series.
nonisolated struct SessionTrimData: Sendable {
  let record: SessionRecord
  let speedChart: WalkSpeedChartContent
  let timeline: TrimTimeline
  let filtered: [RouteFilter.Accumulator]
  let originalMap: TrackingMapContent
  let bounds: MKMapRect
  let route: RouteFilter.Configuration

  init?(record: SessionRecord, route: RouteFilter.Configuration) {
    let filter = RouteFilter(configuration: route)
    let timeline = TrimTimeline(record: record, filter: filter)
    guard let sessionEnd = record.endDate, let end = timeline.dates.last,
      record.trimmed(endingAt: end) != nil
    else { return nil }
    let samples = WalkSpeedSeries.samples(
      for: record, filter: filter, interval: WalkSpeedSeries.defaultInterval)
    speedChart = WalkSpeedChartContent(
      samples: samples, interval: WalkSpeedSeries.defaultInterval,
      range: record.startDate...sessionEnd)
    self.record = record
    self.timeline = timeline
    self.route = route
    filtered = record.segments.map { filter.filter($0.points) }
    originalMap = TrackingMapContent(segments: filtered)
    var bounds = MKMapRect.null
    let coordinates =
      filtered.flatMap { $0.acceptedPoints.map(\.coordinate) }
      + record.segments.compactMap { $0.points.last?.coordinate }
    for coordinate in coordinates {
      let point = MKMapPoint(CLLocationCoordinate2D(coordinate))
      bounds = bounds.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
    }
    self.bounds = bounds.insetBy(
      dx: -max(bounds.width * 0.15, 500), dy: -max(bounds.height * 0.15, 500))
  }
}
