import CoreLocation
import Domain
import Foundation
import MapKit

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
