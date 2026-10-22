import MapKit
import SwiftUI
import Tracking

struct TrackingMapView: View {
  let session: LiveSession?
  let locationAccess: LocationAccessState

  var body: some View {
    // Do not read record (including session.id) here: timing-only changes must not rebuild the map.
    RouteMapView(content: TrackingMapContent(route: session?.route), locationAccess: locationAccess)
  }
}

struct RouteMapView: View {
  let content: TrackingMapContent
  let locationAccess: LocationAccessState
  @State private var position: MapCameraPosition
  @Namespace private var mapScope

  init(
    content: TrackingMapContent, locationAccess: LocationAccessState,
    initialPosition: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
  ) {
    self.content = content
    self.locationAccess = locationAccess
    _position = State(initialValue: initialPosition)
  }

  var body: some View {
    Map(position: $position, scope: mapScope) {
      ForEach(content.segments) { segment in
        MapPolyline(coordinates: segment.coordinates)
          .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
      }
      if showsCurrentLocation { UserAnnotation() }
    }
    .mapControls {
      if showsCurrentLocation { MapUserLocationButton(scope: mapScope) }
      MapCompass(scope: mapScope)
      MapScaleView(scope: mapScope)
    }
    .mapScope(mapScope)
    .accessibilityIdentifier("tracking.map")
  }

  private var showsCurrentLocation: Bool {
    // Viewing the idle map must not request permission before an explicit recording action.
    locationAccess == .available || locationAccess == .fullAccuracyRequired
  }
}

#if DEBUG
  #Preview("Separate segments") {
    RouteMapView(content: .preview(), locationAccess: .denied, initialPosition: .automatic)
  }

  #Preview("No route") {
    RouteMapView(content: TrackingMapContent(route: nil), locationAccess: .notDetermined)
  }
#endif
