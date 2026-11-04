import Domain
import Foundation
import Persistence
import SwiftData
import Testing

@testable import Features

@MainActor
struct SessionTrimIntegrationTests {
  @Test func persistedTrimIsReflectedInSummaryHistoryAndStatistics() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(
      id: id, startDate: TrimFixtures.date(0), timeZone: .init(identifier: "Asia/Tokyo")!)
    for second in stride(from: 0.0, through: 50.0, by: 10.0) {
      try await store.append(TrimFixtures.point(second, north: second), sessionID: id)
    }
    try await store.finish(sessionID: id, at: TrimFixtures.date(60), steps: 100)
    let list: @MainActor @Sendable () throws -> [SessionListItem] = {
      try SessionReader(context: ModelContext(container)).finishedSessions()
    }
    let history = HistoryModel(list: list, deleter: store)
    let statistics = StatisticsModel(list: list, now: { TrimFixtures.date(60) })
    history.load()
    statistics.load()
    statistics.setGranularity(.day)
    statistics.setMetric(.steps)
    let period = statistics.period
    let summary = SessionSummaryModel(
      sessionID: id, route: .default,
      read: {
        try await SessionRecordLoader(container: container).session(id: $0)
      })
    await summary.load()
    let dependencies = SessionTrimDependencies(
      trimmer: store, querySteps: { _, _ in 20 },
      saved: {
        history.load()
        statistics.load()
      })
    let trim = try #require(summary.makeTrimModel(using: dependencies))
    await trim.load()
    trim.select(offset: 20)
    let previewDistance = try #require(trim.distance)
    let previewTiming = try #require(trim.timing)
    await trim.requestSave()
    #expect(await trim.confirmSave())
    dependencies.saved()
    await summary.load()
    guard case .loaded(let data) = summary.state, case .loaded(let sections) = history.state else {
      Issue.record("Expected reloaded walks")
      return
    }
    #expect(data.record.endDate == TrimFixtures.date(20))
    #expect(data.summary.endDate == TrimFixtures.date(20))
    #expect(data.summary.metrics.timing == previewTiming)
    #expect(data.summary.metrics.distance == previewDistance)
    #expect(data.summary.metrics.steps == 20)
    #expect(sections.first?.items.first?.distance == previewDistance)
    #expect(sections.first?.items.first?.steps == 20)
    #expect(statistics.allTime.distance == previewDistance)
    #expect(statistics.allTime.steps == 20)
    #expect(statistics.statistics?.totals.distance == previewDistance)
    #expect(statistics.period == period)
    #expect(statistics.metric == .steps)
    #expect(statistics.granularity == .day)
    let nextTrim = try #require(summary.makeTrimModel(using: dependencies))
    await nextTrim.load()
    #expect(nextTrim.selectedDate == TrimFixtures.date(20))
  }
}
