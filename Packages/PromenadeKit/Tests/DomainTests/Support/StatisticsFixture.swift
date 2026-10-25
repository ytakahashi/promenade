import Foundation

@testable import Domain

enum StatisticsFixture {
  static func calendar(_ timeZone: String = "UTC", firstWeekday: Int = 1) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZone)!
    calendar.firstWeekday = firstWeekday
    calendar.minimumDaysInFirstWeek = 4
    return calendar
  }

  static func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
  }

  static func period(
    containing date: Date, granularity: StatisticsGranularity, calendar: Calendar
  ) -> StatisticsPeriod {
    StatisticsPeriod(containing: date, granularity: granularity, calendar: calendar)!
  }

  static func item(
    _ start: String = "2026-10-24T07:00:00Z", timeZone: String = "UTC",
    id: UUID = UUID(), distance: Double = 1000, duration: TimeInterval = 600,
    steps: Int? = 100
  ) -> SessionListItem {
    SessionListItem(
      id: id, startDate: date(start), timeZoneIdentifier: timeZone,
      distance: distance, walkingDuration: duration, steps: steps)
  }

  static func entry(
    _ start: String = "2026-10-24T07:00:00Z", id: UUID = UUID(),
    distance: Double = 1000, duration: TimeInterval = 600, steps: Int? = 100
  ) -> StatisticsEntry {
    StatisticsEntry(
      item(start, id: id, distance: distance, duration: duration, steps: steps),
      calendar: calendar())
  }

  /// An entry recorded in the time zone of `calendar` itself, so its wall clock is unchanged.
  static func entry(at startDate: Date, calendar: Calendar) -> StatisticsEntry {
    var item = item(timeZone: calendar.timeZone.identifier)
    item.startDate = startDate
    return StatisticsEntry(item, calendar: calendar)
  }
}
