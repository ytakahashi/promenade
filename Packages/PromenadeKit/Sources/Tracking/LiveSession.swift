import Domain
import Foundation
import Observation

@MainActor
@Observable
public final class LiveSession {
  public private(set) var record: SessionRecord
  public private(set) var route: LiveRoute

  init(record: SessionRecord, filter: RouteFilter) {
    self.record = record
    route = LiveRoute(segments: record.segments, filter: filter)
  }

  public var id: UUID { record.id }
  public var lastPoint: TrackPoint? { record.segments.last?.points.last }
  public var lastActivity: Date { record.lastActivityDate }

  public func timing(asOf date: Date) -> SessionTiming {
    SessionMetricsCalculator.timing(
      segments: record.segments, sessionStart: record.startDate, asOf: record.endDate ?? date)
  }

  func append(_ point: TrackPoint) {
    record.segments[record.segments.count - 1].points.append(point)
    route.append(point)
  }

  func close(at date: Date, reason: SegmentEndReason) {
    guard record.hasOpenSegment else { return }
    let index = record.segments.count - 1
    record.segments[index].endDate = date
    record.segments[index].endReason = reason
  }

  func open(at date: Date) {
    record.segments.append(
      SegmentRecord(index: (record.segments.last?.index ?? -1) + 1, startDate: date))
    record.state = .recording
    route.openSegment()
  }

  func pause(at date: Date) {
    if !record.hasOpenSegment { open(at: date) }
    close(at: date, reason: .paused)
    record.state = .paused
  }
}
