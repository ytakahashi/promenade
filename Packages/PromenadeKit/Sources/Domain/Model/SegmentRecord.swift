import Foundation

/// A continuously recorded part of a session.
public struct SegmentRecord: Sendable, Equatable {
  /// Order within the session, starting at 0.
  public var index: Int
  public var startDate: Date
  /// `nil` while the segment is still being recorded.
  public var endDate: Date?
  public var endReason: SegmentEndReason?
  /// `nil` when steps were not measured.
  public var steps: Int?
  /// Sorted by timestamp.
  public var points: [TrackPoint]

  public init(
    index: Int,
    startDate: Date,
    endDate: Date? = nil,
    endReason: SegmentEndReason? = nil,
    steps: Int? = nil,
    points: [TrackPoint] = []
  ) {
    self.index = index
    self.startDate = startDate
    self.endDate = endDate
    self.endReason = endReason
    self.steps = steps
    self.points = points
  }
}
