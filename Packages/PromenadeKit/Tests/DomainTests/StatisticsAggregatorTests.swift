import Foundation
import Testing

@testable import Domain

struct StatisticsAggregatorTests {
  private typealias Fixture = StatisticsFixture

  private func statistics(
    _ entries: [StatisticsEntry], granularity: StatisticsGranularity = .month
  ) -> PeriodStatistics {
    let calendar = Fixture.calendar()
    return StatisticsAggregator.statistics(
      for: Fixture.period(
        containing: Fixture.date("2026-10-24T12:00:00Z"), granularity: granularity,
        calendar: calendar),
      entries: entries, calendar: calendar)
  }

  @Test func emptyPeriodRetainsBucketsAndHasUndefinedAverages() {
    let result = statistics([])
    #expect(result.buckets.count == 31)
    #expect(result.buckets.allSatisfy { $0.totals == .zero })
    #expect(result.totals == .zero)
    #expect(result.walkedDays == 0)
    #expect(result.stepMeasuredDays == 0)
    #expect(result.entries.isEmpty)
    #expect(result.dailyAverage == MetricAverages(distance: nil, walkingDuration: nil, steps: nil))
    #expect(result.perSessionAverage == result.dailyAverage)
  }

  @Test func periodIncludesStartAndExcludesEnd() {
    let entries = [
      Fixture.entry("2026-09-30T23:59:59Z"), Fixture.entry("2026-10-01T00:00:00Z"),
      Fixture.entry("2026-10-31T23:59:59Z"), Fixture.entry("2026-11-01T00:00:00Z"),
    ]
    let result = statistics(entries)
    #expect(result.entries == [entries[1], entries[2]])
    #expect(result.buckets.first?.totals.sessionCount == 1)
    #expect(result.buckets.last?.totals.sessionCount == 1)
    #expect(result.totals.sessionCount == 2)
    #expect(StatisticsAggregator.allTime(entries).sessionCount == 4)
  }

  @Test func entireOvernightWalkBelongsToItsStartingHour() {
    let entry = Fixture.entry("2026-10-24T23:30:00Z", duration: 7200)
    let result = statistics([entry], granularity: .day)
    #expect(result.buckets.last?.totals.walkingDuration == 7200)
    #expect(result.buckets.dropLast().allSatisfy { $0.totals == .zero })
    #expect(result.walkedDays == 1)
  }

  @Test func averagesCountRecordedDaysAndOnlyMeasuredSteps() {
    let result = statistics([
      Fixture.entry("2026-10-01T07:00:00Z", distance: 1000, duration: 100, steps: 100),
      Fixture.entry("2026-10-01T18:00:00Z", distance: 2000, duration: 200, steps: nil),
      Fixture.entry("2026-10-03T07:00:00Z", distance: 3000, duration: 300, steps: 0),
      Fixture.entry("2026-10-05T07:00:00Z", distance: 0, duration: 0, steps: nil),
      Fixture.entry("2026-10-01T19:00:00Z", distance: 0, duration: 0, steps: 200),
    ])
    #expect(result.walkedDays == 3)
    #expect(result.stepMeasuredDays == 2)
    #expect(result.dailyAverage == MetricAverages(distance: 2000, walkingDuration: 200, steps: 150))
    #expect(
      result.perSessionAverage == MetricAverages(distance: 1200, walkingDuration: 120, steps: 100))
    #expect(result.totals.steps == 300)
    #expect(result.totals.stepMeasuredSessionCount == 3)
  }

  @Test func unmeasuredStepsHaveNoAverageButOtherMetricsDo() {
    let result = statistics([Fixture.entry(steps: nil)])
    #expect(result.totals.steps == nil)
    #expect(result.dailyAverage.steps == nil)
    #expect(result.perSessionAverage.steps == nil)
    #expect(result.dailyAverage.distance == 1000)
    #expect(result.perSessionAverage.walkingDuration == 600)
  }

  @Test func sortsByLocalStartThenUUID() {
    let earlier = Fixture.entry("2026-10-24T06:00:00Z")
    let first = Fixture.entry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let second = Fixture.entry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
    #expect(statistics([second, earlier, first]).entries == [earlier, first, second])
  }

  @Test(arguments: [StatisticsGranularity.day, .week, .month, .year])
  func bucketsPartitionEntriesAndPreserveTotals(granularity: StatisticsGranularity) {
    let entries = [
      Fixture.entry("2026-10-24T00:00:00Z", steps: nil),
      Fixture.entry("2026-10-24T06:00:00Z", steps: 0),
      Fixture.entry("2026-10-24T23:59:59Z", steps: 300),
    ]
    let result = statistics(entries, granularity: granularity)
    #expect(result.totals == StatisticsAggregator.allTime(entries))
    #expect(result.buckets.reduce(0) { $0 + $1.totals.distance } == result.totals.distance)
    #expect(
      result.buckets.reduce(0) { $0 + $1.totals.walkingDuration } == result.totals.walkingDuration)
    #expect(result.buckets.reduce(0) { $0 + ($1.totals.steps ?? 0) } == result.totals.steps)
    #expect(result.buckets.reduce(0) { $0 + $1.totals.sessionCount } == entries.count)
    #expect(result.walkedDays == 1)
    for entry in entries {
      let matching = result.buckets.filter { $0.range.contains(entry.localStart) }
      #expect(matching.count == 1)
      #expect(result.bucket(containing: entry.localStart) == matching.first)
    }
  }

  @Test func yearCountsDaysRatherThanMonthBuckets() {
    let result = statistics(
      [
        Fixture.entry("2026-01-01T07:00:00Z"), Fixture.entry("2026-01-02T07:00:00Z"),
        Fixture.entry("2026-02-01T07:00:00Z"),
      ], granularity: .year)
    #expect(result.walkedDays == 3)
    #expect(result.stepMeasuredDays == 3)
    #expect(result.dailyAverage.distance == 1000)
    #expect(result.buckets[0].totals.sessionCount == 2)
    #expect(result.buckets[1].totals.sessionCount == 1)
  }

  @Test(arguments: ["2026-03-08T12:00:00Z", "2026-11-01T12:00:00Z"])
  func bucketLookupUsesHalfOpenRangesIncludingDSTDays(date: String) {
    let calendar = Fixture.calendar("America/Los_Angeles")
    let period = Fixture.period(
      containing: Fixture.date(date), granularity: .day, calendar: calendar)
    let result = StatisticsAggregator.statistics(for: period, entries: [], calendar: calendar)
    for bucket in result.buckets {
      #expect(result.bucket(containing: bucket.start) == bucket)
      #expect(result.bucket(containing: bucket.start.addingTimeInterval(1800)) == bucket)
    }
    #expect(result.bucket(containing: period.interval.start.addingTimeInterval(-1)) == nil)
    #expect(result.bucket(containing: period.interval.end) == nil)
    #expect(
      result.bucket(containing: period.interval.end.addingTimeInterval(-1)) == result.buckets.last)
  }

  @Test(arguments: ["2026-03-08T12:00:00Z", "2026-11-01T12:00:00Z"])
  func everyHourOfADSTDayIsCounted(date: String) {
    let calendar = Fixture.calendar("America/Los_Angeles")
    let period = Fixture.period(
      containing: Fixture.date(date), granularity: .day, calendar: calendar)
    let entries = period.bucketRanges(calendar: calendar).map {
      Fixture.entry(at: $0.lowerBound.addingTimeInterval(1800), calendar: calendar)
    }
    let result = StatisticsAggregator.statistics(
      for: period, entries: entries, calendar: calendar)
    // A repeated wall-clock hour may be normalized into the other occurrence, so only the
    // period's totals are exact; the per-bucket placement of that hour is not.
    #expect(result.totals.sessionCount == entries.count)
    #expect(result.walkedDays == 1)
  }

  /// In America/Santiago, 2026-09-06 starts at 01:00; walks just after the following midnights
  /// must belong to their own day, matching the day count.
  @Test func walksAfterAMissingMidnightBelongToTheirOwnDay() {
    let calendar = Fixture.calendar("America/Santiago")
    let period = Fixture.period(
      containing: Fixture.date("2026-09-07T12:00:00-03:00"), granularity: .week,
      calendar: calendar)
    let entries = [
      Fixture.entry(at: Fixture.date("2026-09-06T01:30:00-03:00"), calendar: calendar),
      Fixture.entry(at: Fixture.date("2026-09-07T00:30:00-03:00"), calendar: calendar),
    ]
    let result = StatisticsAggregator.statistics(
      for: period, entries: entries, calendar: calendar)
    #expect(result.buckets.map(\.totals.sessionCount) == [1, 1, 0, 0, 0, 0, 0])
    #expect(result.walkedDays == 2)
  }
}
