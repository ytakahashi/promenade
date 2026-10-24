import Domain
import Foundation

extension WalkingSession {
  func record() throws -> SessionRecord {
    guard let state = SessionState(rawValue: stateRaw) else {
      throw PersistenceError.invalidStoredValue(field: "stateRaw", value: stateRaw)
    }
    // SwiftData relationship arrays are unordered; Domain requires index order.
    return try SessionRecord(
      id: id, startDate: startDate, endDate: endDate, state: state,
      timeZoneIdentifier: timeZoneIdentifier,
      segments: segments.sorted { $0.index < $1.index }.map { try $0.record() }
    )
  }
}

extension WalkingSession {
  /// Uses the saved metrics only, so it must not touch `segments`.
  func listItem() -> SessionListItem {
    SessionListItem(
      id: id, startDate: startDate, timeZoneIdentifier: timeZoneIdentifier, distance: distance,
      walkingDuration: walkingDuration, steps: steps)
  }
}

extension Segment {
  func record() throws -> SegmentRecord {
    let reason: SegmentEndReason?
    if let raw = endReasonRaw {
      guard let parsed = SegmentEndReason(rawValue: raw) else {
        throw PersistenceError.invalidStoredValue(field: "endReasonRaw", value: raw)
      }
      reason = parsed
    } else {
      reason = nil
    }
    // Relationship order is not preserved by the store, even when points were inserted in order.
    return SegmentRecord(
      index: index, startDate: startDate, endDate: endDate, endReason: reason, steps: steps,
      points: points.sorted { $0.timestamp < $1.timestamp }.map { $0.record() }
    )
  }
}

extension LocationPoint {
  convenience init(point: TrackPoint) {
    self.init(
      timestamp: point.timestamp, latitude: point.coordinate.latitude,
      longitude: point.coordinate.longitude, horizontalAccuracy: point.horizontalAccuracy,
      altitude: point.altitude, verticalAccuracy: point.verticalAccuracy, speed: point.speed,
      speedAccuracy: point.speedAccuracy, course: point.course
    )
  }

  func record() -> TrackPoint {
    TrackPoint(
      timestamp: timestamp, coordinate: Coordinate(latitude: latitude, longitude: longitude),
      horizontalAccuracy: horizontalAccuracy, altitude: altitude,
      verticalAccuracy: verticalAccuracy,
      speed: speed, speedAccuracy: speedAccuracy, course: course
    )
  }
}
