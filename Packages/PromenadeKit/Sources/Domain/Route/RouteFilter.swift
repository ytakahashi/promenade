import Foundation

/// Selects the points used for distance and route drawing, and accumulates the distance.
///
/// Live display and batch recomputation share the same logic: `filter(_:)` is a fold over
/// `Accumulator.add(_:)`. Use one accumulator per segment; distance is never added across segments.
public struct RouteFilter: Sendable {
  /// Thresholds of the filter.
  ///
  /// Distances stored with a session are derived with these values, so changing any of them
  /// requires bumping `DerivedDataVersion.current`.
  public struct Configuration: Sendable, Equatable {
    /// Maximum horizontal accuracy in meters for a point to be used.
    public var maxHorizontalAccuracy: Double
    /// Maximum speed in meters per second from the anchor; faster points are outliers.
    public var maxSpeed: Double
    /// Number of consecutive, mutually consistent speed rejections after which the latest rejected
    /// point becomes the new anchor.
    public var speedRejectionResetCount: Int

    public init(maxHorizontalAccuracy: Double, maxSpeed: Double, speedRejectionResetCount: Int) {
      self.maxHorizontalAccuracy = maxHorizontalAccuracy
      self.maxSpeed = maxSpeed
      self.speedRejectionResetCount = speedRejectionResetCount
    }

    public static let `default` = Configuration(
      maxHorizontalAccuracy: 20,
      maxSpeed: 30 / 3.6,  // 30 km/h
      speedRejectionResetCount: 3
    )
  }

  public var configuration: Configuration

  public init(configuration: Configuration = .default) {
    self.configuration = configuration
  }

  public func makeAccumulator() -> Accumulator {
    Accumulator(configuration: configuration)
  }

  public func filter(_ points: [TrackPoint]) -> Accumulator {
    points.reduce(into: makeAccumulator()) { $0.add($1) }
  }

  public struct Accumulator: Sendable {
    let configuration: Configuration
    /// Points that passed the filter, in the order they were added. The last one is the anchor.
    public private(set) var acceptedPoints: [TrackPoint] = []
    /// Accumulated distance in meters.
    public private(set) var distance: Double = 0
    /// Number of points accepted since the last anchor reset (or since the start).
    private var currentRunLength = 0
    /// The most recent point rejected for speed, while rejections are consecutive.
    private var lastSpeedRejected: TrackPoint?
    private var consecutiveSpeedRejections = 0

    init(configuration: Configuration) {
      self.configuration = configuration
    }

    public mutating func add(_ point: TrackPoint) {
      guard point.horizontalAccuracy >= 0,
        point.horizontalAccuracy <= configuration.maxHorizontalAccuracy
      else { return }

      guard let anchor = acceptedPoints.last else {
        accept(point, distance: 0)
        return
      }

      let interval = point.timestamp.timeIntervalSince(anchor.timestamp)
      guard interval > 0 else { return }

      let d = GeoDistance.meters(from: anchor.coordinate, to: point.coordinate)
      // Movement within the accuracy radius is indistinguishable from jitter while standing still.
      guard d >= max(anchor.horizontalAccuracy, point.horizontalAccuracy) else { return }

      guard d / interval <= configuration.maxSpeed else {
        rejectForSpeed(point)
        return
      }
      accept(point, distance: d)
    }

    private mutating func accept(_ point: TrackPoint, distance d: Double) {
      acceptedPoints.append(point)
      distance += d
      currentRunLength += 1
      lastSpeedRejected = nil
      consecutiveSpeedRejections = 0
    }

    /// If the anchor itself was an outlier, every following point looks too fast and would be
    /// rejected forever. When enough consecutive rejected points agree with each other (i.e. the
    /// position consistently moved elsewhere), the latest one becomes the new anchor. Rejected
    /// points that do not agree are scattered outliers and restart the count, so they never take
    /// over the anchor.
    private mutating func rejectForSpeed(_ point: TrackPoint) {
      if let previous = lastSpeedRejected, isConsistent(point, with: previous) {
        consecutiveSpeedRejections += 1
      } else {
        consecutiveSpeedRejections = 1
      }
      lastSpeedRejected = point

      guard consecutiveSpeedRejections >= configuration.speedRejectionResetCount else { return }

      // An anchor that is the only point of its run (typically the first fix of a segment) is
      // almost certainly the outlier; drop it so the route is not drawn through it. A longer run
      // is kept because it cannot be told which side was wrong. The jump itself is unreliable and
      // is never added to the distance.
      if currentRunLength == 1 {
        acceptedPoints.removeLast()
      }
      acceptedPoints.append(point)
      currentRunLength = 1
      lastSpeedRejected = nil
      consecutiveSpeedRejections = 0
    }

    private func isConsistent(_ point: TrackPoint, with previous: TrackPoint) -> Bool {
      let interval = point.timestamp.timeIntervalSince(previous.timestamp)
      guard interval > 0 else { return false }
      let d = GeoDistance.meters(from: previous.coordinate, to: point.coordinate)
      return d / interval <= configuration.maxSpeed
    }
  }
}
