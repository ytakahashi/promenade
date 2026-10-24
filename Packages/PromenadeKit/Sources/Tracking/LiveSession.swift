import Domain
import Foundation
import Observation

@MainActor
@Observable
public final class LiveSession {
  public private(set) var record: SessionRecord
  public private(set) var route: LiveRoute
  /// Cumulative live steps of the open segment; `nil` until the first value arrives.
  public private(set) var openSegmentSteps: Int?

  init(record: SessionRecord, filter: RouteFilter) {
    self.record = record
    route = LiveRoute(segments: record.segments, filter: filter)
  }

  public var id: UUID { record.id }
  public var lastPoint: TrackPoint? { record.segments.last?.points.last }
  public var lastActivity: Date { record.lastActivityDate }

  /// Steps of closed segments plus the open segment's live value; `nil` if any part is unmeasured
  /// or there are no segments, matching how the finished session's steps are totalled.
  public var steps: Int? {
    guard !record.segments.isEmpty else { return nil }
    var total = 0
    for segment in record.segments {
      guard let steps = segment.endDate == nil ? openSegmentSteps : segment.steps else {
        return nil
      }
      total += steps
    }
    return total
  }

  public func timing(asOf date: Date) -> SessionTiming {
    SessionMetricsCalculator.timing(
      segments: record.segments, sessionStart: record.startDate, asOf: record.endDate ?? date)
  }

  func append(_ point: TrackPoint) {
    record.segments[record.segments.count - 1].points.append(point)
    route.append(point)
  }

  func close(at date: Date, reason: SegmentEndReason, steps: Int?) {
    guard record.hasOpenSegment else { return }
    let index = record.segments.count - 1
    record.segments[index].endDate = date
    record.segments[index].endReason = reason
    record.segments[index].steps = steps
    openSegmentSteps = nil
  }

  /// Ignores values from a subscription for a segment that is no longer open.
  func updateOpenSegmentSteps(_ steps: Int, segmentStart: Date) {
    guard let last = record.segments.last, last.endDate == nil, last.startDate == segmentStart
    else { return }
    openSegmentSteps = steps
  }

  func open(at date: Date) {
    record.segments.append(
      SegmentRecord(index: (record.segments.last?.index ?? -1) + 1, startDate: date))
    record.state = .recording
    route.openSegment()
    openSegmentSteps = nil
  }

  /// Mirrors `TrackingStore.pause`, including zero steps for the empty segment after access loss.
  func pause(at date: Date, steps: Int?) {
    if record.hasOpenSegment {
      close(at: date, reason: .paused, steps: steps)
    } else {
      open(at: date)
      close(at: date, reason: .paused, steps: 0)
    }
    record.state = .paused
  }
}
