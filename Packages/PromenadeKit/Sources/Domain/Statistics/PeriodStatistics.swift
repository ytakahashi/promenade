import Foundation

public struct MetricAverages: Sendable, Equatable {
  /// nil when the denominator is zero.
  public let distance: Double?
  public let walkingDuration: TimeInterval?
  public let steps: Double?
}

public struct PeriodStatistics: Sendable, Equatable {
  public struct Bucket: Sendable, Equatable {
    /// Half-open, so adjacent buckets never share a boundary.
    public let range: Range<Date>
    public let totals: MetricTotals

    public var start: Date { range.lowerBound }
  }

  public let period: StatisticsPeriod
  /// Every bucket of the period in order, including empty ones.
  public let buckets: [Bucket]
  public let totals: MetricTotals
  /// Days with at least one session, including sessions with zero distance or duration.
  public let walkedDays: Int
  public let stepMeasuredDays: Int
  /// Oldest first by localStart, with UUID as a deterministic tie breaker.
  public let entries: [StatisticsEntry]

  /// Per walked day, not per calendar day. Steps use only days with measured steps.
  public var dailyAverage: MetricAverages {
    averages(count: walkedDays, stepCount: stepMeasuredDays)
  }

  public var perSessionAverage: MetricAverages {
    averages(count: totals.sessionCount, stepCount: totals.stepMeasuredSessionCount)
  }

  /// The bucket whose range contains date, or nil outside the period.
  public func bucket(containing date: Date) -> Bucket? {
    buckets.first { $0.range.contains(date) }
  }

  private func averages(count: Int, stepCount: Int) -> MetricAverages {
    // Unmeasured sessions and days must not dilute step averages; measured zeroes do count.
    MetricAverages(
      distance: count > 0 ? totals.distance / Double(count) : nil,
      walkingDuration: count > 0 ? totals.walkingDuration / Double(count) : nil,
      steps: stepCount > 0 ? totals.steps.map { Double($0) / Double(stepCount) } : nil
    )
  }
}
