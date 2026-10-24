import Domain
import Foundation
import Testing

@testable import Features

@MainActor
struct HistorySectionsTests {
  @Test func groupsByMonthNewestFirst() {
    let items = [
      item("2026-10-24T06:00:00+09:00", zone: "Asia/Tokyo"),
      item("2026-10-01T06:00:00+09:00", zone: "Asia/Tokyo"),
      item("2026-09-30T06:00:00+09:00", zone: "Asia/Tokyo"),
      item("2025-12-31T06:00:00+09:00", zone: "Asia/Tokyo"),
    ]
    let sections = HistorySection.make(items)
    #expect(sections.map(\.id) == ["2026-10", "2026-09", "2025-12"])
    #expect(sections[0].items == Array(items[0...1]))
    #expect(sections[0].year == 2026 && sections[0].month == 10)
  }

  @Test func usesTheTimeZoneEachWalkWasRecordedIn() {
    // 00:30 on October 1 in Tokyo is still September in UTC.
    let tokyo = item("2026-10-01T00:30:00+09:00", zone: "Asia/Tokyo")
    let utc = item("2026-09-30T20:00:00Z", zone: "UTC")
    let sections = HistorySection.make([utc, tokyo])
    #expect(sections.map(\.id) == ["2026-10", "2026-09"])
    #expect(sections[0].items == [tokyo])
  }

  @Test func walksAcrossTimeZonesAreSortedWithinTheirMonth() {
    // New York's walk starts later in absolute time but belongs to the earlier month.
    let tokyo = item("2026-11-01T00:30:00+09:00", zone: "Asia/Tokyo")
    let newYork = item("2026-10-31T20:00:00-04:00", zone: "America/New_York")
    let earlier = item("2026-10-31T10:00:00+09:00", zone: "Asia/Tokyo")
    let sections = HistorySection.make([newYork, tokyo, earlier])
    #expect(sections.map(\.id) == ["2026-11", "2026-10"])
    #expect(sections[1].items == [newYork, earlier])
  }

  @Test func invalidTimeZoneFallsBackToTheDevice() {
    // Mid-month, so the month is the same in every device time zone.
    let sections = HistorySection.make([item("2026-10-15T12:00:00Z", zone: "Not/AZone")])
    #expect(sections.map(\.id) == ["2026-10"])
  }

  @Test func emptyListHasNoSections() {
    #expect(HistorySection.make([]).isEmpty)
  }

  @Test func titleFollowsTheLocale() {
    let section = HistorySection(id: "2026-10", year: 2026, month: 10, items: [])
    #expect(section.title(locale: Locale(identifier: "en_US")) == "October 2026")
    #expect(section.title(locale: Locale(identifier: "ja_JP")) == "2026年10月")
  }

  private func item(_ start: String, zone: String) -> SessionListItem {
    SessionListItem(
      id: UUID(), startDate: try! Date(start, strategy: .iso8601), timeZoneIdentifier: zone,
      distance: 1000, walkingDuration: 600, steps: nil)
  }
}
