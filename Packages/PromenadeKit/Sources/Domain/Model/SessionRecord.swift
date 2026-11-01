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

  /// Whether the last segment is still being recorded.
  public var hasOpenSegment: Bool {
    guard let last = segments.last else { return false }
    return last.endDate == nil
  }

  /// Closed segments without measured steps, with the interval their steps cover: a signal gap
  /// counts as walking, so such a segment's steps run up to the next segment's start.
  public var unmeasuredSegments: [(index: Int, start: Date, end: Date)] {
    segments.enumerated().compactMap { position, segment in
      guard segment.steps == nil, let end = segment.endDate else { return nil }
      let next = segments.indices.contains(position + 1) ? segments[position + 1] : nil
      let stepsEnd = segment.endReason == .signalGap ? next?.startDate ?? end : end
      return (segment.index, segment.startDate, stepsEnd)
    }
  }

  /// The latest moment the session is known to have been active.
  ///
  /// Used to decide how to recover an unfinished session after the app was terminated.
  public var lastActivityDate: Date {
    let last = segments.last
    return Self.lastActivityDate(
      startDate: startDate, lastSegmentStart: last?.startDate, lastSegmentEnd: last?.endDate,
      lastPointDate: last?.points.last?.timestamp)
  }

  /// Computes `lastActivityDate` from its inputs, for callers that hold persisted models rather
  /// than a fully mapped record. Recovery dates derived from one are validated against the other,
  /// so both must share this definition.
  public static func lastActivityDate(
    startDate: Date, lastSegmentStart: Date?, lastSegmentEnd: Date?, lastPointDate: Date?
  ) -> Date {
    [startDate, lastSegmentStart, lastSegmentEnd, lastPointDate].compactMap(\.self).max()
      ?? startDate
  }
}
