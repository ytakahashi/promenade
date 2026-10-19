import CoreLocation
import Domain

extension TrackPoint {
  init(location: CLLocation) {
    self.init(
      timestamp: location.timestamp,
      coordinate: Coordinate(
        latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
      horizontalAccuracy: location.horizontalAccuracy, altitude: location.altitude,
      verticalAccuracy: location.verticalAccuracy, speed: location.speed,
      speedAccuracy: location.speedAccuracy, course: location.course)
  }
}
