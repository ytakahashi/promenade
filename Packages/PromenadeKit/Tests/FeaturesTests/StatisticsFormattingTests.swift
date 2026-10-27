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

  /// Interval formatting surrounds the dash with thin spaces whose exact kind may vary by OS.
  private func normalizedSpaces(_ text: String) -> String {
    String(text.map { $0.isWhitespace ? " " : $0 })
  }
}
