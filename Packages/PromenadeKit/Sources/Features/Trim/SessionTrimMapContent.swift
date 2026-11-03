import CoreLocation
import Domain
import Foundation
import MapKit

/// Prepared once; completed segments can reuse their filtered route during selection changes.
nonisolated struct SessionTrimData: Sendable {
  let record: SessionRecord
  let timeline: TrimTimeline
  let filtered: [RouteFilter.Accumulator]
  let originalMap: TrackingMapContent
  let bounds: MKMapRect
  let route: RouteFilter.Configuration

  init?(record: SessionRecord, route: RouteFilter.Configuration) {
    let filter = RouteFilter(configuration: route)
    let timeline = TrimTimeline(record: record, filter: filter)
    guard let end = timeline.dates.last, record.trimmed(endingAt: end) != nil else { return nil }
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

nonisolated struct SessionTrimMapContent: Sendable {
  let bounds: MKMapRect
  let kept: TrackingMapContent
  let removed: TrackingMapContent
  let endpoint: Coordinate
  let start: Coordinate?

  init(data: SessionTrimData, endingAt date: Date) {
    // Dates come from TrimTimeline. Equal timestamps at a boundary belong to the later segment,
    // matching SessionRecord.trimmed rather than joining geometry across a pause.
    let position = data.record.segments.lastIndex {
      $0.points.first.map { $0.timestamp <= date } ?? false
    }!
    bounds = data.bounds
    let segment = data.record.segments[position]
    let prefix = segment.points.prefix { $0.timestamp <= date }
    let filteredPrefix = RouteFilter(configuration: data.route).filter(Array(prefix))
    // Match the saved route across all retained segments. Use a raw location only when no
    // retained point passed the filter, including those recorded before the current segment.
    endpoint =
      filteredPrefix.acceptedPoints.last?.coordinate
      ?? data.filtered.prefix(position).last { !$0.acceptedPoints.isEmpty }?.acceptedPoints.last?
      .coordinate
      ?? prefix.last!.coordinate
    // A later anchor reset may remove a previously accepted point: slicing the fully filtered
    // route would not reproduce the route that will actually be saved.
    var keptSegments = data.originalMap.segments.filter { $0.id < position }
    if filteredPrefix.acceptedPoints.count >= 2 {
      keptSegments.append(
        .init(
          id: position,
          coordinates: filteredPrefix.acceptedPoints.map { CLLocationCoordinate2D($0.coordinate) }))
    }
    kept = TrackingMapContent(segments: keptSegments)
    start =
      data.filtered.prefix(position).lazy.compactMap { $0.acceptedPoints.first?.coordinate }.first
      ?? filteredPrefix.acceptedPoints.first?.coordinate

    // Keep the preceding accepted point as the boundary of the discarded polyline, when present.
    // Build display geometry directly; re-filtering a suffix could choose a different anchor.
    let points = data.filtered[position].acceptedPoints
    let boundary = points.lastIndex { $0.timestamp <= date }
    let suffix = boundary.map { Array(points[$0...]) } ?? points
    var removedSegments: [TrackingMapContent.Segment] = []
    if suffix.count >= 2 {
      removedSegments.append(
        .init(id: position, coordinates: suffix.map { CLLocationCoordinate2D($0.coordinate) }))
    }
    removedSegments += data.originalMap.segments.filter { $0.id > position }
    removed = TrackingMapContent(segments: removedSegments)
  }
}
