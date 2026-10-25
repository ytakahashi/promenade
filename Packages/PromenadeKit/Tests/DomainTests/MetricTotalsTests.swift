import Foundation
import Testing

@testable import Domain

struct MetricTotalsTests {
  @Test func emptyTotalsAreZero() {
    let totals = MetricTotals.zero
    #expect(totals.distance == 0)
    #expect(totals.walkingDuration == 0)
    #expect(totals.steps == 0)
    #expect(totals.sessionCount == 0)
    #expect(totals.stepMeasuredSessionCount == 0)
    #expect(StatisticsAggregator.allTime([]) == totals)
  }

  @Test func unmeasuredStepsRemainUnknownUntilMeasuredStepsArrive() {
    var totals = MetricTotals.zero
    totals.add(StatisticsFixture.entry(steps: nil))
    totals.add(StatisticsFixture.entry(steps: nil))
    #expect(totals.steps == nil)
    #expect(totals.stepMeasuredSessionCount == 0)
    totals.add(StatisticsFixture.entry(steps: 0))
    #expect(totals.steps == 0)
    #expect(totals.stepMeasuredSessionCount == 1)
    totals.add(StatisticsFixture.entry(steps: 50))
    totals.add(StatisticsFixture.entry(steps: nil))
    #expect(totals.steps == 50)
    #expect(totals.sessionCount == 5)
    #expect(totals.stepMeasuredSessionCount == 2)
    #expect(totals.distance == 5000)
    #expect(totals.walkingDuration == 3000)
  }

  @Test func totalsDoNotDependOnWhetherUnmeasuredEntriesComeFirst() {
    let entries = [StatisticsFixture.entry(steps: nil), StatisticsFixture.entry(steps: 50)]
    #expect(
      StatisticsAggregator.allTime(entries) == StatisticsAggregator.allTime(entries.reversed()))
  }
}
