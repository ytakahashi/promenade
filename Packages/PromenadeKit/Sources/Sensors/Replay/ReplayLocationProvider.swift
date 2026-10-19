#if DEBUG
  import Domain
  import Foundation
  import Synchronization

  /// Replay uses wall-clock timestamps. Speed changes also change apparent route speed and gaps;
  /// use a multiplier of one when checking route filters or signal-gap thresholds.
  ///
  /// The replay timeline starts at the first subscription and keeps running across subscriptions,
  /// like a real walk: subscribing again (e.g. after a pause) continues with the points not yet
  /// due instead of restarting from the beginning.
  public struct ReplayLocationProvider: LocationProvider {
    private let points: [TrackPoint]
    private let offsets: [TimeInterval]
    private let timeline: ReplayTimeline

    public init(points: [TrackPoint], speedMultiplier: Double = 1) throws {
      try self.init(
        points: points, speedMultiplier: speedMultiplier, makeClock: { SystemReplayClock() })
    }

    init(
      points: [TrackPoint], speedMultiplier: Double,
      makeClock: @escaping @Sendable () -> any ReplayClock
    ) throws {
      guard speedMultiplier.isFinite, speedMultiplier > 0 else {
        throw GPXError.invalidSpeedMultiplier
      }
      guard let first = points.first else { throw GPXError.noTrackPoints }
      var offsets: [TimeInterval] = []
      for point in points {
        let offset = point.timestamp.timeIntervalSince(first.timestamp) / speedMultiplier
        // Validate scaling and keep nanosecond clock deadlines within a signed 64-bit range.
        guard offset.isFinite, offset >= 0, offset < Double(Int64.max / 1_000_000_000),
          offsets.last.map({ offset > $0 }) ?? true
        else { throw GPXError.invalidReplayTimeline }
        offsets.append(offset)
      }
      self.points = points
      self.offsets = offsets
      self.timeline = ReplayTimeline(makeClock: makeClock)
    }

    public func events() -> AsyncThrowingStream<LocationEvent, any Error> {
      AsyncThrowingStream { continuation in
        let task = Task {
          do {
            let (clock, isFirstSubscription) = timeline.clock()
            let start = clock.startDate
            // The first subscription plays from the beginning; a real clock has already advanced
            // by a few microseconds and would otherwise skip the first point.
            let resumeOffset = isFirstSubscription ? 0 : await clock.elapsed()
            var previousTimestamp: Date?
            for (point, offset) in zip(points, offsets) where offset >= resumeOffset {
              try Task.checkCancellation()
              // Absolute deadlines avoid accumulating processing overhead across a long replay.
              try await clock.sleep(until: offset)
              try Task.checkCancellation()
              var point = point
              point.timestamp = start.addingTimeInterval(offset)
              guard point.timestamp.timeIntervalSinceReferenceDate.isFinite,
                previousTimestamp.map({ point.timestamp > $0 }) ?? true
              else { throw GPXError.invalidReplayTimeline }
              previousTimestamp = point.timestamp
              continuation.yield(.location(point, stationary: false))
            }
            continuation.finish()
          } catch {
            continuation.finish(throwing: error)
          }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
      }
    }
  }

  /// Shares one clock among all subscriptions (and copies) of a provider.
  private final class ReplayTimeline: Sendable {
    private let makeClock: @Sendable () -> any ReplayClock
    private let current = Mutex<(any ReplayClock)?>(nil)

    init(makeClock: @escaping @Sendable () -> any ReplayClock) {
      self.makeClock = makeClock
    }

    /// Returns the shared clock, creating it on the first call.
    func clock() -> (clock: any ReplayClock, isFirstSubscription: Bool) {
      current.withLock { current in
        if let existing = current { return (existing, false) }
        let created = makeClock()
        current = created
        return (created, true)
      }
    }
  }

  protocol ReplayClock: Sendable {
    var startDate: Date { get }
    /// Seconds since `startDate` on the replay timeline.
    func elapsed() async -> TimeInterval
    func sleep(until offset: TimeInterval) async throws
  }

  private struct SystemReplayClock: ReplayClock {
    let startDate = Date()
    private let origin = ContinuousClock.now

    func elapsed() async -> TimeInterval {
      let duration = origin.duration(to: .now)
      return Double(duration.components.seconds)
        + Double(duration.components.attoseconds) / 1e18
    }

    func sleep(until offset: TimeInterval) async throws {
      try await Task.sleep(until: origin.advanced(by: .seconds(offset)), clock: .continuous)
    }
  }
#endif
