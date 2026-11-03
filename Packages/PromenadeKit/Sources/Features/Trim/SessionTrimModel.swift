import Domain
import Foundation
import Observation
import Persistence

@Observable
final class SessionTrimModel {
  enum Phase: Equatable {
    case loading, unavailable, editing, querying, confirming, saving, saved
  }

  struct Confirmation: Equatable {
    let date: Date
    let fallbackSteps: Int?
    let stepsAvailable: Bool
  }

  private(set) var phase = Phase.loading
  private(set) var data: SessionTrimData?
  private(set) var selectedIndex: Int?
  private(set) var map: SessionTrimMapContent?
  private(set) var mapDate: Date?
  private(set) var confirmation: Confirmation?
  private(set) var saveFailed = false
  @ObservationIgnored private let record: SessionRecord
  @ObservationIgnored private let route: RouteFilter.Configuration
  @ObservationIgnored private let trimmer: any SessionTrimming
  @ObservationIgnored private let querySteps: @MainActor (Date, Date) async throws -> Int?
  @ObservationIgnored private var preparation = 0

  init(
    record: SessionRecord, route: RouteFilter.Configuration, trimmer: any SessionTrimming,
    querySteps: @escaping @MainActor (Date, Date) async throws -> Int?
  ) {
    self.record = record
    self.route = route
    self.trimmer = trimmer
    self.querySteps = querySteps
  }

  var selectedDate: Date? { selectedIndex.flatMap { data?.timeline.dates[$0] } }
  var distance: Double? { selectedIndex.flatMap { data?.timeline.distances[$0] } }
  var timing: SessionTiming? {
    guard let selectedDate else { return nil }
    return SessionMetricsCalculator.timing(
      segments: record.segments, sessionStart: record.startDate, asOf: selectedDate)
  }
  var timeZone: TimeZone { TimeZone(identifier: record.timeZoneIdentifier) ?? .current }
  var canSave: Bool {
    guard phase == .editing, let selectedIndex, let data else { return false }
    return selectedIndex < data.timeline.dates.count - 1
  }
  var isSaving: Bool { phase == .saving }
  var sliderRange: ClosedRange<Double> {
    0...max(1, (record.endDate ?? record.startDate).timeIntervalSince(record.startDate))
  }
  var selectedOffset: Double { selectedDate?.timeIntervalSince(record.startDate) ?? 0 }

  func load() async {
    guard data == nil else { return }
    let prepared = await Self.prepare(record: record, route: route)
    guard !Task.isCancelled, data == nil else { return }
    guard let prepared else {
      phase = .unavailable
      return
    }
    data = prepared.0
    selectedIndex = prepared.0.timeline.dates.count - 1
    map = prepared.1
    mapDate = selectedDate
    phase = .editing
  }

  func select(offset: Double) {
    guard phase == .editing, let data, offset.isFinite else { return }
    let date = record.startDate.addingTimeInterval(min(max(offset, 0), sliderRange.upperBound))
    selectedIndex = data.timeline.candidate(atOrBefore: date) ?? 0
    saveFailed = false
  }

  /// The view's task is replaced on selection changes. Also check the date so a provider of work
  /// that ignores cancellation cannot apply geometry for an earlier selection.
  func refreshMap() async {
    guard let data, let date = selectedDate, mapDate != date else { return }
    let content = await Self.makeMap(data: data, date: date)
    guard !Task.isCancelled, selectedDate == date else { return }
    map = content
    mapDate = date
  }

  func requestSave() async {
    guard canSave, let date = selectedDate else { return }
    preparation += 1
    let request = preparation
    phase = .querying
    saveFailed = false
    do {
      guard var trimmed = await Self.trim(record: record, date: date),
        let last = trimmed.segments.last
      else {
        phase = .editing
        return
      }
      try Task.checkCancellation()
      guard request == preparation else { return }
      let fallback = last.steps == nil ? try await querySteps(last.startDate, date) : nil
      try Task.checkCancellation()
      guard request == preparation else { return }
      trimmed.segments[trimmed.segments.count - 1].steps = last.steps ?? fallback
      confirmation = Confirmation(
        date: date, fallbackSteps: fallback,
        stepsAvailable: trimmed.segments.allSatisfy { $0.steps != nil })
      phase = .confirming
    } catch {
      guard request == preparation else { return }
      phase = .editing
      // Measurement failures are normally returned as nil by StepQuery. Unexpected errors also
      // leave the walk untouched and allow retry; cancellation is never a save failure.
      saveFailed = !(error is CancellationError)
    }
  }

  func cancelConfirmation() {
    guard phase == .confirming else { return }
    confirmation = nil
    phase = .editing
  }

  /// Invalidates pending preparation when the screen disappears. A durable write is not
  /// cancellable: its result must still be delivered even if the caller's task is cancelled.
  func leave() {
    preparation += 1
    if phase == .querying || phase == .confirming {
      confirmation = nil
      phase = .editing
    }
  }

  func confirmSave() async -> Bool {
    guard phase == .confirming, let confirmation else { return false }
    phase = .saving
    self.confirmation = nil
    do {
      try await trimmer.trimEnd(
        sessionID: record.id, at: confirmation.date, steps: confirmation.fallbackSteps)
      phase = .saved
      return true
    } catch {
      phase = .editing
      saveFailed = true
      return false
    }
  }

  func dismissFailure() { saveFailed = false }

  @concurrent private nonisolated static func prepare(
    record: SessionRecord, route: RouteFilter.Configuration
  ) async -> (SessionTrimData, SessionTrimMapContent)? {
    guard let data = SessionTrimData(record: record, route: route),
      let date = data.timeline.dates.last
    else { return nil }
    return (data, SessionTrimMapContent(data: data, endingAt: date))
  }

  @concurrent private nonisolated static func makeMap(data: SessionTrimData, date: Date) async
    -> SessionTrimMapContent
  {
    SessionTrimMapContent(data: data, endingAt: date)
  }

  @concurrent private nonisolated static func trim(record: SessionRecord, date: Date) async
    -> SessionRecord?
  {
    record.trimmed(endingAt: date)
  }
}
