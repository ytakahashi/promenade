import Domain
import Foundation
import SwiftData
import Testing

@testable import Persistence

enum Fixtures {
  static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
  static let timeZone = TimeZone(identifier: "Asia/Tokyo")!

  static func date(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

  static func point(_ seconds: TimeInterval, north: Double = 0, accuracy: Double = 5) -> TrackPoint
  {
    TrackPoint(
      timestamp: date(seconds),
      coordinate: Coordinate(latitude: 35 + north / 6_371_008.8 * 180 / .pi, longitude: 139),
      horizontalAccuracy: accuracy, altitude: 42, verticalAccuracy: 3, speed: 1.2,
      speedAccuracy: 0.2, course: 90)
  }

  static func read<T>(
    _ id: UUID, in container: ModelContainer, body: (WalkingSession) throws -> T
  ) throws -> T {
    let context = ModelContext(container)
    let session = try #require(
      context.fetch(
        FetchDescriptor<WalkingSession>(
          predicate: #Predicate { $0.id == id })
      ).first)
    return try body(session)
  }

  static func record(_ id: UUID, in container: ModelContainer) throws -> SessionRecord {
    try read(id, in: container) { try $0.record() }
  }

  static func storedPointCount(in container: ModelContainer) throws -> Int {
    try ModelContext(container).fetchCount(FetchDescriptor<LocationPoint>())
  }
}
