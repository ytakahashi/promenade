import Domain
import Foundation
import Observation

@Observable
final class StatisticsModel {
  enum State: Equatable {
    case loading, empty, loaded, failed
  }

  private(set) var state = State.loading
  private(set) var granularity = StatisticsGranularity.week
  private(set) var metric = StatisticsMetric.distance
  /// An absolute instant, not a wall-clock day. After a westward time zone change, a past period
  /// may reopen one period earlier; accepted because it is rare and one arrow tap away.
  private(set) var anchorDate: Date
  private(set) var calendar: Calendar
  private(set) var statistics: PeriodStatistics?
  private(set) var allTime = MetricTotals.zero
  private(set) var selectedBucketStart: Date?
  private(set) var itemsByID: [UUID: SessionListItem] = [:]
  private var entries: [StatisticsEntry] = []
  private var today: Date
  private var earliest: Date?
  private var latest: Date?
  @ObservationIgnored private var hasLoadedEntries = false
  @ObservationIgnored private let list: @MainActor () throws -> [SessionListItem]
  @ObservationIgnored private let readCalendar: @MainActor () -> Calendar
  @ObservationIgnored private let now: @MainActor () -> Date

  init(
    list: @escaping @MainActor () throws -> [SessionListItem],
    calendar: @escaping @MainActor () -> Calendar = { .current },
    now: @escaping @MainActor () -> Date = { .now }
  ) {
    self.list = list
    self.readCalendar = calendar
    self.now = now
    self.calendar = calendar()
    let date = now()
    self.today = date
    self.anchorDate = date
  }

  var period: StatisticsPeriod? { statistics?.period }
  var canMoveBackward: Bool { destination(by: -1) != nil }
  var canMoveForward: Bool { destination(by: 1) != nil }

  func load() {
    selectedBucketStart = nil
    do {
      let items = try list()
      calendar = readCalendar()
      let previousToday = today
      today = now()
      // The model may be created long before its tab first appears. Later loads keep a past
      // period the user chose, but follow the new day from the current period; moves and
      // granularity changes keep `anchorDate == today` while on the current period.
      if !hasLoadedEntries || anchorDate == previousToday { anchorDate = today }
      entries = items.map { StatisticsEntry($0, calendar: calendar) }
      itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
      earliest = entries.map(\.localStart).min()
      latest = entries.map(\.localStart).max()
      allTime = StatisticsAggregator.allTime(entries)
      guard !entries.isEmpty else {
        statistics = nil
        state = .empty
        return
      }
      rebuild()
      if state == .loaded { hasLoadedEntries = true }
    } catch {
      entries = []
      itemsByID = [:]
      earliest = nil
      latest = nil
      statistics = nil
      allTime = .zero
      state = .failed
    }
  }

  func setGranularity(_ value: StatisticsGranularity) {
    guard granularity != value else { return }
    granularity = value
    selectedBucketStart = nil
    if state == .loaded { rebuild() }
  }

  func setMetric(_ value: StatisticsMetric) {
    guard metric != value else { return }
    metric = value
    selectedBucketStart = nil
  }

  func selectBucket(containing date: Date?) {
    selectedBucketStart = date.flatMap { statistics?.bucket(containing: $0)?.start }
  }

  func moveBackward() { move(by: -1) }
  func moveForward() { move(by: 1) }

  private func makePeriod(containing date: Date) -> StatisticsPeriod? {
    StatisticsPeriod(containing: date, granularity: granularity, calendar: calendar)
  }

  private var bounds: (lower: StatisticsPeriod, upper: StatisticsPeriod)? {
    // Include today even when travel places every recorded wall clock in the future.
    guard let lower = makePeriod(containing: min(earliest ?? today, today)),
      let upper = makePeriod(containing: max(latest ?? today, today))
    else { return nil }
    return (lower, upper)
  }

  private func destination(by offset: Int) -> StatisticsPeriod? {
    guard state == .loaded, let period, let bounds,
      let target = period.moved(by: offset, calendar: calendar),
      target.interval.start >= bounds.lower.interval.start,
      target.interval.start <= bounds.upper.interval.start
    else { return nil }
    return target
  }

  private func move(by offset: Int) {
    guard let target = destination(by: offset) else { return }
    anchorDate = containsToday(target) ? today : target.interval.start
    selectedBucketStart = nil
    rebuild()
  }

  private func containsToday(_ period: StatisticsPeriod) -> Bool {
    period.interval.start <= today && today < period.interval.end
  }

  private func rebuild() {
    guard var target = makePeriod(containing: anchorDate), let bounds else {
      // Only reachable when the calendar cannot place a date. There is nothing else to show, so
      // it reuses the read failure state even though the read itself succeeded.
      statistics = nil
      state = .failed
      return
    }
    if target.interval.start < bounds.lower.interval.start {
      target = bounds.lower
      anchorDate = containsToday(target) ? today : target.interval.start
    } else if target.interval.start > bounds.upper.interval.start {
      target = bounds.upper
      anchorDate = containsToday(target) ? today : target.interval.start
    }
    // Cache aggregation: metric changes and chart selection must not scan every session.
    statistics = StatisticsAggregator.statistics(for: target, entries: entries, calendar: calendar)
    state = .loaded
  }
}
