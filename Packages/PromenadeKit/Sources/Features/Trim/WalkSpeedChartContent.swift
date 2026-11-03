import Domain
import Foundation

/// Interval averages drawn as separate runs of steps, in meters per second.
nonisolated struct WalkSpeedChartContent: Sendable, Equatable {
  struct Point: Identifiable, Sendable, Equatable {
    let id: Int
    let date: Date
    let speed: Double
  }

  struct Run: Identifiable, Sendable, Equatable {
    let id: Int
    let points: [Point]
  }

  let runs: [Run]
  let range: ClosedRange<Date>
  /// Includes a floor of 1 m/s so stationary or empty walks have a usable, unit-independent axis.
  let upperBound: Double

  /// Samples are the ascending, fixed-width intervals returned by WalkSpeedSeries.
  init(samples: [SpeedSample], interval: TimeInterval, range: ClosedRange<Date>) {
    precondition(interval.isFinite && interval > 0, "The interval must be finite and positive")
    // Match the slider's minimum span for a zero-length walk.
    self.range = range.lowerBound...max(range.upperBound, range.lowerBound.addingTimeInterval(1))
    var runs: [Run] = []
    var points: [Point] = []
    var maximum = 0.0
    for sample in samples {
      let start = max(sample.start, range.lowerBound)
      let end = min(sample.start.addingTimeInterval(interval), range.upperBound)
      guard let speed = sample.speed, speed.isFinite, speed >= 0, start < end else {
        if !points.isEmpty {
          runs.append(Run(id: runs.count, points: points))
          points = []
        }
        continue
      }
      if let previous = points.last, previous.date != start {
        runs.append(Run(id: runs.count, points: points))
        points = []
      }
      // Give each bin its full width, including isolated bins. Adjacent bins share a timestamp
      // with different speeds, producing a vertical step; nil bins must never connect runs.
      points.append(Point(id: points.count, date: start, speed: speed))
      points.append(Point(id: points.count, date: end, speed: speed))
      maximum = max(maximum, speed)
    }
    if !points.isEmpty { runs.append(Run(id: runs.count, points: points)) }
    self.runs = runs
    upperBound = max(1, maximum * 1.1)
  }
}
