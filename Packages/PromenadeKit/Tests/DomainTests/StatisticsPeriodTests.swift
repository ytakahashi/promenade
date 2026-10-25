import Foundation
import Testing

@testable import Domain

struct StatisticsPeriodTests {
  private typealias Fixture = StatisticsFixture

  @Test(arguments: [
    (StatisticsGranularity.day, "2026-10-24T00:00:00Z", "2026-10-25T00:00:00Z", 24),
    (.week, "2026-10-18T00:00:00Z", "2026-10-25T00:00:00Z", 7),
    (.month, "2026-10-01T00:00:00Z", "2026-11-01T00:00:00Z", 31),
    (.year, "2026-01-01T00:00:00Z", "2027-01-01T00:00:00Z", 12),
  ])
  func intervalsAndBuckets(
    granularity: StatisticsGranularity, start: String, end: String, count: Int
  ) {
    let calendar = Fixture.calendar()
    let period = Fixture.period(
      containing: Fixture.date("2026-10-24T07:00:00Z"), granularity: granularity, calendar: calendar
    )
    #expect(period.interval.start == Fixture.date(start))
    #expect(period.interval.end == Fixture.date(end))
    let ranges = period.bucketRanges(calendar: calendar)
    #expect(ranges.count == count)
    expectContiguous(ranges, covering: period)
  }

  @Test func weekFollowsFirstWeekdayAcrossYearBoundary() {
    let calendar = Fixture.calendar(firstWeekday: 2)
    let period = Fixture.period(
      containing: Fixture.date("2027-01-01T12:00:00Z"), granularity: .week, calendar: calendar)
    #expect(period.interval.start == Fixture.date("2026-12-28T00:00:00Z"))
    #expect(period.interval.end == Fixture.date("2027-01-04T00:00:00Z"))
  }

  @Test(arguments: [StatisticsGranularity.day, .week, .month, .year])
  func movesByCalendarUnitsAndCanReturn(granularity: StatisticsGranularity) {
    let calendar = Fixture.calendar()
    let period = Fixture.period(
      containing: Fixture.date("2026-12-31T23:00:00Z"), granularity: granularity, calendar: calendar
    )
    #expect(period.moved(by: 1, calendar: calendar)?.interval.start == period.interval.end)
    #expect(period.moved(by: 1, calendar: calendar)?.moved(by: -1, calendar: calendar) == period)
    #expect(period.moved(by: 0, calendar: calendar) == period)
    #expect(period.moved(by: -2, calendar: calendar)?.moved(by: 2, calendar: calendar) == period)
  }

  @Test func leapFebruaryAndMonthMovement() throws {
    let calendar = Fixture.calendar()
    let period = Fixture.period(
      containing: Fixture.date("2024-01-31T12:00:00Z"), granularity: .month, calendar: calendar)
    let february = try #require(period.moved(by: 1, calendar: calendar))
    #expect(february.bucketRanges(calendar: calendar).count == 29)
    #expect(february.interval.start == Fixture.date("2024-02-01T00:00:00Z"))
    #expect(february.interval.end == Fixture.date("2024-03-01T00:00:00Z"))
  }

  @Test(arguments: [("2026-03-08T12:00:00Z", 23), ("2026-11-01T12:00:00Z", 25)])
  func dstDayBucketsAndMovement(date: String, count: Int) {
    let calendar = Fixture.calendar("America/Los_Angeles")
    let period = Fixture.period(
      containing: Fixture.date(date), granularity: .day, calendar: calendar)
    let ranges = period.bucketRanges(calendar: calendar)
    #expect(ranges.count == count)
    #expect(ranges.allSatisfy { $0.upperBound.timeIntervalSince($0.lowerBound) == 3600 })
    expectContiguous(ranges, covering: period)
    #expect(period.moved(by: 1, calendar: calendar)?.interval.start == period.interval.end)
    #expect(period.moved(by: 1, calendar: calendar)?.moved(by: -1, calendar: calendar) == period)
  }

  /// In America/Santiago, clocks jump from 00:00 to 01:00 on 2026-09-06, so that day starts at
  /// 01:00 while every later day starts at midnight.
  @Test(arguments: [StatisticsGranularity.week, .month])
  func bucketsAfterAMissingMidnightStartAtMidnight(granularity: StatisticsGranularity) {
    let calendar = Fixture.calendar("America/Santiago")
    let period = Fixture.period(
      containing: Fixture.date("2026-09-07T12:00:00-03:00"), granularity: granularity,
      calendar: calendar)
    let ranges = period.bucketRanges(calendar: calendar)
    expectContiguous(ranges, covering: period)
    #expect(ranges.allSatisfy { $0.lowerBound == calendar.startOfDay(for: $0.lowerBound) })
    #expect(ranges.contains { $0.lowerBound == Fixture.date("2026-09-06T01:00:00-03:00") })
    #expect(ranges.contains { $0.lowerBound == Fixture.date("2026-09-07T00:00:00-03:00") })
  }

  private func expectContiguous(
    _ ranges: [Range<Date>], covering period: StatisticsPeriod,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(ranges.first?.lowerBound == period.interval.start, sourceLocation: sourceLocation)
    #expect(ranges.last?.upperBound == period.interval.end, sourceLocation: sourceLocation)
    #expect(ranges.allSatisfy { !$0.isEmpty }, sourceLocation: sourceLocation)
    #expect(
      zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound },
      sourceLocation: sourceLocation)
  }
}
