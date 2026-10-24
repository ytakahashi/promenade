import Foundation

/// A finished session as shown in a list, built from its saved metrics without segments or points.
public struct SessionListItem: Sendable, Equatable, Identifiable {
  public var id: UUID
  public var startDate: Date
  /// The time zone at recording time, used for display.
  public var timeZoneIdentifier: String
  /// Filtered route distance in meters.
  public var distance: Double
  public var walkingDuration: TimeInterval
  /// `nil` when steps were not measured.
  public var steps: Int?

  public init(
    id: UUID,
    startDate: Date,
    timeZoneIdentifier: String,
    distance: Double,
    walkingDuration: TimeInterval,
    steps: Int?
  ) {
    self.id = id
    self.startDate = startDate
    self.timeZoneIdentifier = timeZoneIdentifier
    self.distance = distance
    self.walkingDuration = walkingDuration
    self.steps = steps
  }
}
