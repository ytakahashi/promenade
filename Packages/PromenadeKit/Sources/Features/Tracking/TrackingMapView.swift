import MapKit
import SwiftUI
import Tracking

struct TrackingMapView: View {
  let session: LiveSession?
  let locationAccess: LocationAccessState

  var body: some View {
    // Do not read record (including session.id) here: timing-only changes must not rebuild the map.
    RouteMapView(
      content: TrackingMapContent(route: session?.route), camera: .followsUser(locationAccess)
    )
    .accessibilityIdentifier("tracking.map")
  }
}

struct RouteMapView: View {
  enum CameraPolicy: Equatable {
    /// Follows the device until the user moves the map. The device location is shown only when
    /// access is already usable.
    case followsUser(LocationAccessState)
    /// Frames the whole route. A saved walk is unrelated to where the device is now, so the
    /// device location is neither shown nor followed.
    case fitsRoute
  }

  let content: TrackingMapContent
  let camera: CameraPolicy
  @State private var position: MapCameraPosition
  @Namespace private var mapScope

  init(
    content: TrackingMapContent, camera: CameraPolicy, initialPosition: MapCameraPosition? = nil
  ) {
    self.content = content
    self.camera = camera
    let defaultPosition: MapCameraPosition =
      switch camera {
      case .followsUser: .userLocation(followsHeading: false, fallback: .automatic)
      case .fitsRoute: .automatic
      }
    _position = State(initialValue: initialPosition ?? defaultPosition)
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
  }

  private var showsCurrentLocation: Bool {
    guard case .followsUser(let access) = camera else { return false }
    // Viewing the idle map must not request permission before an explicit recording action.
    return access == .available || access == .fullAccuracyRequired
  }
}

#if DEBUG
  #Preview("Separate segments") {
    RouteMapView(content: .preview(), camera: .fitsRoute)
  }

  #Preview("No route") {
    RouteMapView(content: TrackingMapContent(route: nil), camera: .followsUser(.notDetermined))
  }
#endif
