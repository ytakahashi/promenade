import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
  static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
  static var models: [any PersistentModel.Type] {
    [WalkingSession.self, Segment.self, LocationPoint.self]
  }

  @Model final class WalkingSession {
    #Unique<WalkingSession>([\.id])
    #Index<WalkingSession>([\.startDate])

    var id: UUID
    var startDate: Date
    var endDate: Date?
    var stateRaw: String
    var timeZoneIdentifier: String
    var distance: Double = 0
    var walkingDuration: TimeInterval = 0
    var pauseDuration: TimeInterval = 0
    var interruptionDuration: TimeInterval = 0
    var steps: Int?
    // Zero denotes metrics that have not yet been finalized.
    var derivedDataVersion: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \Segment.session)
    var segments: [Segment] = []

    init(id: UUID, startDate: Date, stateRaw: String, timeZoneIdentifier: String) {
      self.id = id
      self.startDate = startDate
      self.stateRaw = stateRaw
      self.timeZoneIdentifier = timeZoneIdentifier
    }
  }

  @Model final class Segment {
    var id: UUID
    var index: Int
    var startDate: Date
    var endDate: Date?
    var endReasonRaw: String?
    var steps: Int?
    var session: WalkingSession?
    @Relationship(deleteRule: .cascade, inverse: \LocationPoint.segment)
    var points: [LocationPoint] = []

    init(id: UUID = UUID(), index: Int, startDate: Date) {
      self.id = id
      self.index = index
      self.startDate = startDate
    }
  }

  @Model final class LocationPoint {
    #Index<LocationPoint>([\.timestamp])

    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var altitude: Double
    var verticalAccuracy: Double
    var speed: Double
    var speedAccuracy: Double
    var course: Double
    var segment: Segment?

    init(
      timestamp: Date, latitude: Double, longitude: Double, horizontalAccuracy: Double,
      altitude: Double, verticalAccuracy: Double, speed: Double, speedAccuracy: Double,
      course: Double
    ) {
      self.timestamp = timestamp
      self.latitude = latitude
      self.longitude = longitude
      self.horizontalAccuracy = horizontalAccuracy
      self.altitude = altitude
      self.verticalAccuracy = verticalAccuracy
      self.speed = speed
      self.speedAccuracy = speedAccuracy
      self.course = course
    }
  }
}

// Keep SwiftData model types inside Persistence; callers exchange Domain values.
typealias WalkingSession = SchemaV1.WalkingSession
typealias Segment = SchemaV1.Segment
typealias LocationPoint = SchemaV1.LocationPoint
