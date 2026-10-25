import Foundation

public struct MetricTotals: Sendable, Equatable {
  public private(set) var distance: Double = 0
  public private(set) var walkingDuration: TimeInterval = 0
  /// nil when no session has measured steps; 0 when the group is empty.
  public private(set) var steps: Int? = 0
  public private(set) var sessionCount: Int = 0
  public private(set) var stepMeasuredSessionCount: Int = 0

  public static let zero = MetricTotals()

  private init() {}

  public mutating func add(_ entry: StatisticsEntry) {
    distance += entry.distance
    walkingDuration += entry.walkingDuration
    sessionCount += 1
    if let measuredSteps = entry.steps {
      stepMeasuredSessionCount += 1
      steps = (steps ?? 0) + measuredSteps
    } else if stepMeasuredSessionCount == 0 {
      // An empty group means no walking; a nonempty unmeasured group means unknown steps.
      steps = nil
    }
  }
}
