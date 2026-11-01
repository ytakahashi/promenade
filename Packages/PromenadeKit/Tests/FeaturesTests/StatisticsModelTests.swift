import Domain
import Foundation
import Testing

@testable import Features

@MainActor
struct StatisticsModelTests {
  @Test func loadsAndReloadsSavedMetrics() throws {
    let source = StatisticsSource([item(20), item(21, steps: nil)])
    let model = makeModel(source)
    #expect(model.state == .loading)
    model.load()
    #expect(model.state == .loaded)
    #expect(model.granularity == .week)
    #expect(model.metric == .distance)
    #expect(model.allTime.sessionCount == 2)
    #expect(model.allTime.steps == 1200)
    #expect(model.statistics?.dailyAverage.steps == 1200)
    #expect(model.itemsByID.count == 2)
    source.items = [item(22)]
    model.load()
    #expect(source.reads == 2)
    #expect(model.allTime.sessionCount == 1)
    #expect(model.statistics?.entries.count == 1)
  }

  @Test func firstAppearanceUsesTodayRatherThanModelCreationTime() {
    let source = StatisticsSource([item(20)])
    var currentDate = date(3)
    let calendar = calendar
    let model = StatisticsModel(list: source.list, calendar: { calendar }, now: { currentDate })
    currentDate = date(24, hour: 12)
    model.load()
    #expect(model.anchorDate == currentDate)
    #expect(model.statistics?.totals.sessionCount == 1)
  }

  @Test func emptyAndFailedReadsClearStaleDataAndCanRetry() {
    let source = StatisticsSource([item(20)])
    let model = makeModel(source)
    model.load()
    source.fails = true
    model.load()
    #expect(model.state == .failed)
    #expect(model.statistics == nil)
    #expect(model.allTime == .zero)
    #expect(model.itemsByID.isEmpty)
    source.fails = false
    source.items = []
    model.load()
    #expect(model.state == .empty)
    source.items = [item(20)]
    model.load()
    #expect(model.state == .loaded)
  }

  @Test func navigationStopsAtBoundsAndReturnsToTodayWithoutFetching() throws {
    let source = StatisticsSource([item(2)])
    let model = makeModel(source)
    model.load()
    #expect(!model.canMoveForward)
    model.moveBackward()
    #expect(model.canMoveForward)
    model.moveBackward()
    model.moveBackward()
    #expect(!model.canMoveBackward)
    let first = model.period
    model.moveBackward()
    #expect(model.period == first)
    model.moveForward()
    model.moveForward()
    model.moveForward()
    #expect(model.anchorDate == date(24, hour: 12))
    model.setGranularity(.day)
    #expect(model.period?.interval.start == date(24))
    #expect(model.statistics?.totals == .zero)
    #expect(model.statistics?.dailyAverage.distance == nil)
    #expect(source.reads == 1)
  }

  @Test func granularityPreservesAnchorAndSelectionDoesNotChangeStatistics() throws {
    let source = StatisticsSource([item(20)])
    let model = makeModel(source)
    model.load()
    let original = try #require(model.statistics)
    model.toggleBucket(containing: date(20, hour: 14))
    #expect(model.selectedBucketStart == date(20))
    #expect(model.statistics == original)
    model.setMetric(.steps)
    #expect(model.selectedBucketStart == nil)
    #expect(model.statistics == original)
    model.toggleBucket(containing: original.period.interval.end)
    #expect(model.selectedBucketStart == nil)
    model.toggleBucket(containing: date(20))
    model.setGranularity(.month)
    #expect(model.selectedBucketStart == nil)
    #expect(model.anchorDate == date(24, hour: 12))
    model.setGranularity(.day)
    #expect(model.period?.interval.start == date(24))
    #expect(model.metric == .steps)
    #expect(source.reads == 1)
  }

  @Test func tappingTheSelectedBucketOrOutsideThePeriodClearsSelection() throws {
    let model = makeModel(StatisticsSource([item(20)]))
    model.load()
    let periodEnd = try #require(model.period?.interval.end)
    model.toggleBucket(containing: date(20, hour: 14))
    #expect(model.selectedBucketStart == date(20))
    // A different instant inside the same bucket is still the same bucket.
    model.toggleBucket(containing: date(20, hour: 9))
    #expect(model.selectedBucketStart == nil)
    model.toggleBucket(containing: date(20, hour: 9))
    model.toggleBucket(containing: date(21, hour: 9))
    #expect(model.selectedBucketStart == date(21))
    model.toggleBucket(containing: periodEnd)
    #expect(model.selectedBucketStart == nil)
    model.toggleBucket(containing: date(21))
    model.toggleBucket(containing: nil)
    #expect(model.selectedBucketStart == nil)
  }

  @Test func granularityKeepsThePastPeriodStartAsAnchor() {
    let source = StatisticsSource([item(2), item(20)])
    let model = makeModel(source)
    model.load()
    model.moveBackward()
    #expect(model.anchorDate == date(11))
    model.setGranularity(.day)
    #expect(model.period?.interval.start == date(11))
    model.setGranularity(.month)
    #expect(model.period?.interval.start == date(1))
    #expect(model.anchorDate == date(11))
  }

  @Test func reloadFollowsTheNewDayOnlyFromTheCurrentPeriod() {
    let source = StatisticsSource([item(2), item(20)])
    var currentDate = date(24, hour: 12)
    let calendar = calendar
    let model = StatisticsModel(list: source.list, calendar: { calendar }, now: { currentDate })
    model.load()
    currentDate = date(26, hour: 9)
    model.load()
    #expect(model.anchorDate == currentDate)
    #expect(model.period?.interval.start == date(25))
    #expect(!model.canMoveForward)
    model.moveBackward()
    currentDate = date(27, hour: 9)
    model.load()
    #expect(model.anchorDate == date(18))
    #expect(model.period?.interval.start == date(18))
  }

  @Test func futureWallClockRemainsReachableAndBoundsUseLocalStarts() {
    // Both original instants are Oct 24 UTC, but their recorded dates span two days.
    let west = SessionListItem(
      id: UUID(), startDate: date(24, hour: 2), timeZoneIdentifier: "America/Los_Angeles",
      distance: 100, walkingDuration: 60, steps: nil)
    let east = SessionListItem(
      id: UUID(), startDate: date(24, hour: 23), timeZoneIdentifier: "Asia/Tokyo",
      distance: 100, walkingDuration: 60, steps: 0)
    let model = makeModel(StatisticsSource([east, west]))
    model.load()
    model.setGranularity(.day)
    #expect(model.canMoveBackward)
    #expect(model.canMoveForward)
    model.moveForward()
    #expect(model.period?.interval.start == date(25))
    #expect(!model.canMoveForward)
    #expect(model.statistics?.entries.map(\.id) == [east.id])
    model.moveBackward()
    model.moveBackward()
    #expect(model.period?.interval.start == date(23))
    #expect(!model.canMoveBackward)
    #expect(model.statistics?.entries.map(\.id) == [west.id])
  }

  @Test func todayIsReachableWhenEveryEntryIsInTheFuture() {
    let model = makeModel(StatisticsSource([item(25)]))
    model.load()
    model.setGranularity(.day)
    #expect(!model.canMoveBackward)
    #expect(model.canMoveForward)
    model.moveForward()
    model.moveBackward()
    #expect(model.anchorDate == date(24, hour: 12))
  }

  @Test func reloadClampsDeletedPeriodsAndResetsSelection() {
    let source = StatisticsSource([item(2), item(20)])
    let model = makeModel(source)
    model.load()
    model.moveBackward()
    model.moveBackward()
    model.moveBackward()
    model.toggleBucket(containing: date(2))
    source.items = [item(20)]
    model.load()
    #expect(model.selectedBucketStart == nil)
    #expect(model.anchorDate == date(24, hour: 12))
    #expect(!model.canMoveBackward)
    #expect(!model.canMoveForward)
  }

  @Test func reloadKeepsAnchorAndRefreshesCalendarAndNow() {
    let source = StatisticsSource([item(2), item(20)])
    var currentCalendar = calendar
    var currentDate = date(24, hour: 12)
    let model = StatisticsModel(
      list: source.list, calendar: { currentCalendar }, now: { currentDate })
    model.load()
    model.moveBackward()
    let anchor = model.anchorDate
    model.setMetric(.duration)
    currentCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    currentCalendar.firstWeekday = 2
    currentDate = date(25)
    model.load()
    #expect(model.calendar == currentCalendar)
    #expect(model.anchorDate == anchor)
    #expect(model.metric == .duration)
    #expect(
      model.period
        == StatisticsPeriod(containing: anchor, granularity: .week, calendar: currentCalendar))
    #expect(model.allTime.sessionCount == 2)
  }

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    calendar.minimumDaysInFirstWeek = 1
    return calendar
  }

  private func date(_ day: Int, hour: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
  }

  private func item(_ day: Int, steps: Int? = 1200) -> SessionListItem {
    SessionListItem(
      id: UUID(), startDate: date(day, hour: 7), timeZoneIdentifier: "GMT",
      distance: 1000, walkingDuration: 600, steps: steps)
  }

  private func makeModel(_ source: StatisticsSource) -> StatisticsModel {
    let calendar = calendar
    let today = date(24, hour: 12)
    return StatisticsModel(list: source.list, calendar: { calendar }, now: { today })
  }
}

@MainActor
private final class StatisticsSource {
  var items: [SessionListItem]
  var fails = false
  private(set) var reads = 0

  init(_ items: [SessionListItem]) { self.items = items }

  func list() throws -> [SessionListItem] {
    reads += 1
    if fails { throw CocoaError(.fileReadUnknown) }
    return items
  }
}
