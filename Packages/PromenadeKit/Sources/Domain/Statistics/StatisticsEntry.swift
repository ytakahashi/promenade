import Foundation

/// A session placed on the viewer's calendar by its wall-clock start at recording time.
public struct StatisticsEntry: Sendable, Equatable, Identifiable {
  public let id: UUID
  /// Recording-time wall clock reinterpreted in the aggregation calendar's time zone.
  public let localStart: Date
  /// Saved distance in meters.
  public let distance: Double
  public let walkingDuration: TimeInterval
  public let steps: Int?

  public init(_ item: SessionListItem, calendar: Calendar) {
    var recordingCalendar = calendar
    recordingCalendar.timeZone =
      TimeZone(identifier: item.timeZoneIdentifier) ?? calendar.timeZone
    let components = recordingCalendar.dateComponents(
      [.era, .year, .month, .day, .hour, .minute, .second, .nanosecond], from: item.startDate)
    // Preserve the recorded wall clock so grouping agrees with History after travel. This date
    // is not the original instant and must never be used to recalculate session metrics.
    // Calendar normalizes nonexistent or repeated local times at daylight-saving transitions.
    // If reconstruction still fails, the original instant is the closest placement available.
    self.localStart = calendar.date(from: components) ?? item.startDate
    self.id = item.id
    self.distance = item.distance
    self.walkingDuration = item.walkingDuration
    self.steps = item.steps
  }
}
