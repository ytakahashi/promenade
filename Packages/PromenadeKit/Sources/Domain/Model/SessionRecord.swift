import Foundation

/// A walking session from Start to Finish.
public struct SessionRecord: Sendable, Equatable {
  public var id: UUID
  public var startDate: Date
  /// `nil` until the session is finished.
  public var endDate: Date?
  public var state: SessionState
  /// The time zone at recording time, used for display.
  public var timeZoneIdentifier: String
  /// Sorted by index.
  public var segments: [SegmentRecord]

  public init(
    id: UUID,
    startDate: Date,
    endDate: Date? = nil,
    state: SessionState,
    timeZoneIdentifier: String,
    segments: [SegmentRecord] = []
  ) {
    self.id = id
    self.startDate = startDate
    self.endDate = endDate
    self.state = state
    self.timeZoneIdentifier = timeZoneIdentifier
    self.segments = segments
  }

  /// The latest moment the session is known to have been active.
  ///
  /// Used to decide how to recover an unfinished session after the app was terminated.
  public var lastActivityDate: Date {
    guard let last = segments.last else { return startDate }
    let candidates = [startDate, last.startDate, last.endDate, last.points.last?.timestamp]
    return candidates.compactMap(\.self).max() ?? startDate
  }
}
