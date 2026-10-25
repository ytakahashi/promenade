import Foundation
import Testing

@testable import Domain

struct StatisticsEntryTests {
  private typealias Fixture = StatisticsFixture

  @Test func preservesRecordingWallClockAndSavedMetrics() {
    let item = Fixture.item("2026-10-23T22:00:00Z", timeZone: "Asia/Tokyo", steps: nil)
    let entry = StatisticsEntry(item, calendar: Fixture.calendar())
    #expect(entry.localStart == Fixture.date("2026-10-24T07:00:00Z"))
    #expect(entry.id == item.id)
    #expect(entry.distance == item.distance)
    #expect(entry.walkingDuration == item.walkingDuration)
    #expect(entry.steps == nil)
  }

  @Test func invalidTimeZoneFallsBackToInjectedCalendar() {
    let item = Fixture.item(timeZone: "invalid")
    let entry = StatisticsEntry(item, calendar: Fixture.calendar("Asia/Tokyo"))
    #expect(entry.localStart == item.startDate)
  }

  @Test func usesTheSameCalendarSystemForExtractionAndReconstruction() {
    var calendar = Calendar(identifier: .buddhist)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let item = Fixture.item("2026-10-23T22:00:00Z", timeZone: "Asia/Tokyo")
    #expect(
      StatisticsEntry(item, calendar: calendar).localStart
        == Fixture.date("2026-10-24T07:00:00Z"))
  }

  @Test func normalizesNonexistentDSTTime() {
    let calendar = Fixture.calendar("America/Los_Angeles")
    let entry = StatisticsEntry(
      Fixture.item("2026-03-08T02:30:00Z"), calendar: calendar)
    let components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute], from: entry.localStart)
    #expect(components.year == 2026)
    #expect(components.month == 3)
    #expect(components.day == 8)
    #expect(components.hour == 3)
    #expect(components.minute == 30)
  }

  @Test func repeatedDSTTimeBelongsToOneOfTheRepeatedHours() {
    let entry = StatisticsEntry(
      Fixture.item("2026-11-01T01:30:00Z"),
      calendar: Fixture.calendar("America/Los_Angeles"))
    #expect(
      [Fixture.date("2026-11-01T08:30:00Z"), Fixture.date("2026-11-01T09:30:00Z")]
        .contains(entry.localStart))
  }

  @Test func reinterpretedWallClockCanBeLaterThanTheOriginalInstant() {
    let item = Fixture.item("2026-10-23T22:00:00Z", timeZone: "Asia/Tokyo")
    let entry = StatisticsEntry(item, calendar: Fixture.calendar("America/Los_Angeles"))
    #expect(entry.localStart == Fixture.date("2026-10-24T14:00:00Z"))
    #expect(entry.localStart > item.startDate)
  }
}
