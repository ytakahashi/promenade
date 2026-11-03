import Domain
import Foundation
import Persistence
import Testing

@testable import Features

@MainActor
struct SessionTrimModelTests {
  @Test func selectionSnapsToPointsAndOnlyEarlierCandidatesCanSave() async throws {
    let record = TrimFixtures.record()
    let model = makeModel(record)
    await model.load()
    #expect(model.phase == .editing)
    #expect(model.selectedDate == TrimFixtures.date(50))
    #expect(!model.canSave)
    model.select(offset: 25)
    #expect(model.selectedDate == TrimFixtures.date(10))
    #expect(model.canSave)
    let trimmed = try #require(record.trimmed(endingAt: TrimFixtures.date(10)))
    let metrics = SessionMetricsCalculator.metrics(
      for: trimmed, filter: .init(), asOf: TrimFixtures.date(10))
    #expect(model.distance == metrics.distance)
    #expect(model.timing == metrics.timing)
    model.select(offset: -10)
    #expect(model.selectedDate == TrimFixtures.date(0))
    model.select(offset: 1000)
    #expect(model.selectedDate == TrimFixtures.date(50))
    #expect(!model.canSave)
    model.select(offset: .nan)
    #expect(model.selectedDate == TrimFixtures.date(50))
  }

  @Test func previewMetricsMatchSavedMetricsAtEveryCandidate() async throws {
    let record = TrimFixtures.record()
    let model = makeModel(record)
    await model.load()
    for date in try #require(model.data).timeline.dates {
      model.select(offset: date.timeIntervalSince(record.startDate))
      let trimmed = try #require(record.trimmed(endingAt: date))
      let metrics = SessionMetricsCalculator.metrics(for: trimmed, filter: .init(), asOf: date)
      #expect(model.distance == metrics.distance)
      #expect(model.timing == metrics.timing)
    }
  }

  @Test func retainedStepsSkipQueryAndUseNilFallback() async throws {
    let store = TrimTestStore()
    var queries = 0
    let model = makeModel(TrimFixtures.record(), store: store) { _, _ in
      queries += 1
      return 999
    }
    await model.load()
    model.select(offset: 10)
    await model.requestSave()
    #expect(queries == 0)
    #expect(model.confirmation?.stepsAvailable == true)
    #expect(model.confirmation?.fallbackSteps == nil)
    #expect(await model.confirmSave())
    #expect(await store.calls == [.init(date: TrimFixtures.date(10), steps: nil)])
    #expect(model.phase == .saved)
    #expect(await !model.confirmSave())
  }

  @Test(arguments: [Optional(7), nil])
  func shortenedSegmentQueriesOnlyTheRetainedInterval(steps: Int?) async throws {
    let store = TrimTestStore()
    var ranges: [ClosedRange<Date>] = []
    let model = makeModel(TrimFixtures.record(), store: store) { start, end in
      ranges.append(start...end)
      return steps
    }
    await model.load()
    model.select(offset: 40)
    await model.requestSave()
    #expect(ranges == [TrimFixtures.date(30)...TrimFixtures.date(40)])
    #expect(model.confirmation?.stepsAvailable == (steps != nil))
    #expect(await model.confirmSave())
    #expect(await store.calls == [.init(date: TrimFixtures.date(40), steps: steps)])
  }

  @Test func earlierUnmeasuredSegmentStillWarnsWhenLastQuerySucceeds() async {
    var record = TrimFixtures.record()
    record.segments[0].steps = nil
    let model = makeModel(record) { _, _ in 5 }
    await model.load()
    model.select(offset: 40)
    await model.requestSave()
    #expect(model.confirmation?.stepsAvailable == false)
    #expect(model.confirmation?.fallbackSteps == 5)
  }

  @Test func cancelConfirmationDoesNotWriteAndCanSelectAgain() async {
    let store = TrimTestStore()
    let model = makeModel(TrimFixtures.record(), store: store)
    await model.load()
    model.select(offset: 10)
    await model.requestSave()
    model.select(offset: 40)
    #expect(model.selectedDate == TrimFixtures.date(10))
    model.cancelConfirmation()
    #expect(await !model.confirmSave())
    #expect(await store.calls.isEmpty)
    model.select(offset: 40)
    #expect(model.selectedDate == TrimFixtures.date(40))
  }

  @Test func queryErrorReturnsToEditingWithoutWriting() async {
    let store = TrimTestStore()
    let model = makeModel(TrimFixtures.record(), store: store) { _, _ in
      throw TrimTestStore.Failure.injected
    }
    await model.load()
    model.select(offset: 40)
    await model.requestSave()
    #expect(model.phase == .editing)
    #expect(model.saveFailed)
    #expect(model.confirmation == nil)
    #expect(model.selectedDate == TrimFixtures.date(40))
    #expect(model.canSave)
    #expect(await store.calls.isEmpty)
  }

  @Test func leavingDuringConfirmationDiscardsItWithoutWriting() async {
    let store = TrimTestStore()
    let model = makeModel(TrimFixtures.record(), store: store)
    await model.load()
    model.select(offset: 10)
    await model.requestSave()
    #expect(model.phase == .confirming)
    #expect(model.confirmation != nil)
    model.leave()
    #expect(model.phase == .editing)
    #expect(model.confirmation == nil)
    #expect(await !model.confirmSave())
    #expect(await store.calls.isEmpty)
  }

  @Test func failedSaveKeepsSelectionAndCanRetry() async {
    let store = TrimTestStore()
    await store.failNext()
    let model = makeModel(TrimFixtures.record(), store: store)
    await model.load()
    model.select(offset: 40)
    await model.requestSave()
    #expect(await !model.confirmSave())
    #expect(model.saveFailed)
    #expect(model.canSave)
    #expect(model.selectedDate == TrimFixtures.date(40))
    model.dismissFailure()
    await model.requestSave()
    #expect(await model.confirmSave())
    #expect(await store.calls.count == 2)
  }

  @Test func leavingDuringQueryIgnoresLateResultAndPreventsDuplicateRequests() async {
    let gate = TrimQueryGate()
    let model = makeModel(TrimFixtures.record()) { _, _ in await gate.wait() }
    await model.load()
    model.select(offset: 40)
    let task = Task.immediate { await model.requestSave() }
    await gate.arrival()
    #expect(model.phase == .querying)
    await model.requestSave()
    #expect(gate.count == 1)
    model.leave()
    gate.release(8)
    await task.value
    #expect(model.phase == .editing)
    #expect(model.confirmation == nil)
    #expect(!model.saveFailed)
  }

  @Test func cancellationDuringQueryDoesNotShowFailureOrConfirmation() async {
    let gate = TrimQueryGate()
    let model = makeModel(TrimFixtures.record()) { _, _ in await gate.wait() }
    await model.load()
    model.select(offset: 40)
    let task = Task.immediate { await model.requestSave() }
    await gate.arrival()
    task.cancel()
    gate.release(8)
    await task.value
    #expect(model.phase == .editing)
    #expect(model.confirmation == nil)
    #expect(!model.saveFailed)
  }

  @Test func savingLocksSelectionAndCompletesDespiteCallerCancellation() async {
    let store = TrimTestStore()
    await store.holdNext()
    let model = makeModel(TrimFixtures.record(), store: store)
    await model.load()
    model.select(offset: 40)
    await model.requestSave()
    let saving = Task.immediate { await model.confirmSave() }
    await store.waitUntilHeld()
    #expect(model.isSaving)
    model.select(offset: 10)
    await model.requestSave()
    #expect(await !model.confirmSave())
    #expect(model.selectedDate == TrimFixtures.date(40))
    #expect(await store.calls.count == 1)
    saving.cancel()
    model.leave()
    await store.release()
    #expect(await saving.value)
    #expect(model.phase == .saved)
  }

  @Test func staleMapCannotReplaceTheLatestSelection() async {
    let model = makeModel(TrimFixtures.record())
    await model.load()
    model.select(offset: 10)
    let earlier = Task.immediate { await model.refreshMap() }
    model.select(offset: 40)
    await model.refreshMap()
    await earlier.value
    #expect(model.mapDate == TrimFixtures.date(40))
    #expect(model.map?.endpoint == TrimFixtures.point(40, north: 40).coordinate)
  }

  @Test func invalidRecordsAreUnavailableAndSingleCandidateCannotSave() async {
    var record = TrimFixtures.record()
    record.state = .paused
    let unfinished = makeModel(record)
    await unfinished.load()
    #expect(unfinished.phase == .unavailable)
    record.state = .finished
    record.segments = []
    let empty = makeModel(record)
    await empty.load()
    #expect(empty.phase == .unavailable)
    record.segments = [
      .init(
        index: 0, startDate: record.startDate, endDate: TrimFixtures.date(60), endReason: .finished,
        points: [TrimFixtures.point(0)])
    ]
    let single = makeModel(record)
    await single.load()
    #expect(single.phase == .editing)
    #expect(!single.canSave)
    await single.requestSave()
    #expect(single.phase == .editing)
  }

  private func makeModel(
    _ record: SessionRecord, store: TrimTestStore = TrimTestStore(),
    query: @escaping @MainActor (Date, Date) async throws -> Int? = { _, _ in nil }
  ) -> SessionTrimModel {
    SessionTrimModel(record: record, route: .default, trimmer: store, querySteps: query)
  }
}

actor TrimTestStore: SessionTrimming {
  struct Call: Equatable {
    let date: Date
    let steps: Int?
  }
  enum Failure: Error { case injected }
  private var fails = false
  private var shouldHold = false
  private var held: CheckedContinuation<Void, Never>?
  func holdNext() { shouldHold = true }
  func waitUntilHeld() async { while held == nil { await Task.yield() } }
  func release() {
    held?.resume()
    held = nil
  }
  private(set) var calls: [Call] = []
  func failNext() { fails = true }
  func trimEnd(sessionID: UUID, at date: Date, steps: Int?) async throws {
    calls.append(.init(date: date, steps: steps))
    if shouldHold {
      shouldHold = false
      await withCheckedContinuation { held = $0 }
    }
    if fails {
      fails = false
      throw Failure.injected
    }
  }
}

@MainActor
private final class TrimQueryGate {
  var count = 0
  private var continuation: CheckedContinuation<Int?, Never>?
  func wait() async -> Int? {
    count += 1
    return await withCheckedContinuation { continuation = $0 }
  }
  func arrival() async { while continuation == nil { await Task.yield() } }
  func release(_ steps: Int?) {
    continuation?.resume(returning: steps)
    continuation = nil
  }
}

nonisolated enum TrimFixtures {
  static func date(_ seconds: Double) -> Date {
    Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
  }
  static func point(_ seconds: Double, north: Double = 0, accuracy: Double = 5) -> TrackPoint {
    TrackPoint(
      timestamp: date(seconds), coordinate: .init(latitude: 35 + north / 111_195, longitude: 139),
      horizontalAccuracy: accuracy, altitude: 0, verticalAccuracy: -1, speed: -1, speedAccuracy: -1,
      course: -1)
  }
  static func record() -> SessionRecord {
    SessionRecord(
      id: UUID(), startDate: date(0), endDate: date(60), state: .finished,
      timeZoneIdentifier: "Asia/Tokyo",
      segments: [
        .init(
          index: 0, startDate: date(0), endDate: date(10), endReason: .paused, steps: 10,
          points: [point(0), point(10, north: 10)]),
        .init(
          index: 1, startDate: date(30), endDate: date(60), endReason: .finished, steps: 30,
          points: [point(30, north: 30), point(40, north: 40), point(50, north: 50)]),
      ])
  }
}
