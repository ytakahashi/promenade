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
      guard segment.steps == nil, let end = stepsEnd(ofSegmentAt: position) else { return nil }
      return (segment.index, segment.startDate, end)
    }
  }

  /// The end of the interval a closed segment's steps cover, or `nil` for an open segment.
  private func stepsEnd(ofSegmentAt position: Int) -> Date? {
    let segment = segments[position]
    guard let end = segment.endDate else { return nil }
    let next = segments.indices.contains(position + 1) ? segments[position + 1] : nil
    return segment.endReason == .signalGap ? next?.startDate ?? end : end
  }

  /// The finished session as if it ended at `date`, or `nil` when it cannot end there: it is
  /// unfinished, or `date` is not between the first point and the end of a segment that has points.
  ///
  /// Dates in a gap are rejected because closing a segment there would turn the gap into walking
  /// time. Every recorded point's time is valid, since a segment never ends before its last point.
  public func trimmed(endingAt date: Date) -> SessionRecord? {
    guard state == .finished, let sessionEnd = endDate, date <= sessionEnd,
      let position = segments.lastIndex(where: { segment in
        segment.points.first.map { $0.timestamp <= date } ?? false
      }),
      let stepsEnd = stepsEnd(ofSegmentAt: position),
      let segmentEnd = segments[position].endDate, date <= segmentEnd
    else { return nil }

    var result = self
    result.endDate = date
    result.segments.removeSubrange((position + 1)...)
    result.segments[position].points.removeAll { $0.timestamp > date }
    result.segments[position].endDate = date
    result.segments[position].endReason = .finished
    // Saved steps that run past the new end cannot be split. A signal gap's steps run up to the
    // next segment, so they run past its end even when the segment itself is not shortened.
    if stepsEnd > date {
      result.segments[position].steps = nil
    }
    return result
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
