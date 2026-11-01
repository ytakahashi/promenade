import Domain
import Foundation
import Testing

@testable import Features

@MainActor
struct StatisticsFormattingTests {
  @Test func titlesUseTheAggregationCalendarAndTimeZone() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    calendar.firstWeekday = 1
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 24)))
    let formatting = StatisticsFormatting(locale: Locale(identifier: "en_US"), calendar: calendar)
    let expected: [(StatisticsGranularity, String)] = [
      (.day, "Sat, Oct 24, 2026"), (.week, "Oct 18 – 24, 2026"), (.month, "October 2026"),
      (.year, "2026"),
    ]
    for (granularity, title) in expected {
      let period = try #require(
        StatisticsPeriod(containing: date, granularity: granularity, calendar: calendar))
      #expect(normalizedSpaces(formatting.title(for: period)) == title)
    }
  }

  @Test func weekTitleIncludesBothYearsAcrossNewYear() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    calendar.firstWeekday = 1
    let date = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
    let period = try #require(
      StatisticsPeriod(containing: date, granularity: .week, calendar: calendar))
    let title = StatisticsFormatting(locale: Locale(identifier: "en_US"), calendar: calendar).title(
      for: period)
    #expect(normalizedSpaces(title) == "Dec 27, 2026 – Jan 2, 2027")
  }

  @Test func valuesDistinguishUnknownAndZeroAndRoundAverageSteps() {
    let formatting = StatisticsFormatting(
      locale: Locale(identifier: "en_US@measure=metric"), calendar: .current)
    #expect(formatting.value(nil, metric: .steps) == "--")
    #expect(formatting.value(0, metric: .steps) == "0")
    #expect(formatting.value(1234.6, metric: .steps) == "1,235")
    #expect(formatting.value(0, metric: .distance) == "0.00 km")
    #expect(formatting.value(0, metric: .duration) == "0m")
    #expect(formatting.value(16680, metric: .duration) == "4h 38m")
    #expect(
      StatisticsFormatting(locale: Locale(identifier: "en_US"), calendar: .current).value(
        1609.344, metric: .distance) == "1.00 mi")
  }

  @Test func chartValuesUseDisplayUnitsWithoutChangingSummaryUnits() {
    let metric = StatisticsFormatting(
      locale: Locale(identifier: "en_US@measure=metric"), calendar: .current)
    let miles = StatisticsFormatting(locale: Locale(identifier: "en_US"), calendar: .current)
    #expect(metric.chartValue(1500, metric: .distance, granularity: .week) == 1.5)
    #expect(miles.chartValue(1609.344, metric: .distance, granularity: .week) == 1)
    #expect(metric.chartValue(5400, metric: .duration, granularity: .month) == 90)
    #expect(metric.chartValue(5400, metric: .duration, granularity: .year) == 1.5)
    #expect(metric.chartValue(1200, metric: .steps, granularity: .year) == 1200)
    #expect(metric.chartUnit(metric: .distance, granularity: .week) == "km")
    #expect(miles.chartUnit(metric: .distance, granularity: .week) == "mi")
    #expect(metric.chartUnit(metric: .duration, granularity: .year) == "h")
    #expect(metric.chartUnit(metric: .duration, granularity: .day) == "min")
  }

  @Test func chartUpperBoundAddsHeadroomAndKeepsAFloorForSmallValues() {
    let formatting = StatisticsFormatting(
      locale: Locale(identifier: "en_US@measure=metric"), calendar: .current)
    func bound(_ maximum: Double, _ metric: StatisticsMetric, _ granularity: StatisticsGranularity)
      -> Double
    {
      formatting.chartUpperBound(maximum: maximum, metric: metric, granularity: granularity)
    }
    #expect(bound(0, .distance, .week) == 1)
    #expect(bound(0, .steps, .week) == 10)
    #expect(bound(3, .steps, .day) == 10)
    #expect(bound(0, .duration, .month) == 10)
    #expect(bound(0, .duration, .year) == 1)
    #expect(abs(bound(2000, .steps, .week) - 2200) < 0.001)
    #expect(abs(bound(5000, .distance, .week) - 5.5) < 0.001)
    #expect(abs(bound(7200, .duration, .year) - 2.2) < 0.001)
  }

  @Test func selectionValuePluralizesMeasuredStepsOnly() {
    let formatting = StatisticsFormatting(locale: Locale(identifier: "en_US"), calendar: .current)
    func totals(steps: [Int?]) -> MetricTotals {
      var totals = MetricTotals.zero
      for value in steps {
        let item = SessionListItem(
          id: UUID(), startDate: .now, timeZoneIdentifier: "UTC", distance: 1609.344,
          walkingDuration: 3600, steps: value)
        totals.add(StatisticsEntry(item, calendar: .current))
      }
      return totals
    }
    #expect(formatting.selectionValue(.zero, metric: .steps) == "0 steps")
    #expect(formatting.selectionValue(totals(steps: [1]), metric: .steps) == "1 step")
    #expect(formatting.selectionValue(totals(steps: [5120]), metric: .steps) == "5,120 steps")
    #expect(formatting.selectionValue(totals(steps: [nil]), metric: .steps) == "--")
    #expect(formatting.selectionValue(totals(steps: [1]), metric: .distance) == "1.00 mi")
    #expect(formatting.selectionValue(totals(steps: [1]), metric: .duration) == "1h")
  }

  @Test func axisAndSelectionLabelsUseTheAggregationTimeZone() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let start = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 6)))
    let formatting = StatisticsFormatting(locale: Locale(identifier: "en_US"), calendar: calendar)
    #expect(formatting.axisLabel(start, granularity: .day) == "6")
    #expect(formatting.axisLabel(start, granularity: .week) == "Sat")
    #expect(formatting.axisLabel(start, granularity: .month) == "24")
    #expect(formatting.axisLabel(start, granularity: .year) == "O")
    #expect(
      formatting.bucketTitle(start..<start.addingTimeInterval(3600), granularity: .day).contains(
        "6:00"))
    // The last hour ends on the next day, which must not bring dates into the title.
    let lastHour = start.addingTimeInterval(17 * 3600)
    let lastHourTitle = formatting.bucketTitle(
      lastHour..<lastHour.addingTimeInterval(3600), granularity: .day)
    #expect(lastHourTitle.contains("11:00"))
    #expect(!lastHourTitle.contains("2026"))
    #expect(
      formatting.bucketTitle(start..<start.addingTimeInterval(3600), granularity: .week) == "Oct 24"
    )
  }

  /// Interval formatting surrounds the dash with thin spaces whose exact kind may vary by OS.
  private func normalizedSpaces(_ text: String) -> String {
    String(text.map { $0.isWhitespace ? " " : $0 })
  }
}
