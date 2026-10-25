#if DEBUG
  import Domain
  import Foundation
  import SwiftData
  import Testing

  @testable import Persistence

  @MainActor
  struct DebugSessionSeederTests {
    private var calendar: Calendar { Self.calendar(Fixtures.timeZone.identifier) }

    private static func calendar(_ timeZone: String) -> Calendar {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: timeZone)!
      return calendar
    }

    /// Los Angeles is also the zone used for traveled walks, so it must pick another one.
    @Test(arguments: ["Asia/Tokyo", "America/Los_Angeles"])
    func seedsRequestedCountWithConsistentFinishedSessions(deviceTimeZone: String) throws {
      let calendar = Self.calendar(deviceTimeZone)
      let container = try ModelContainerFactory.make(inMemory: true)
      try DebugSessionSeeder.seed(
        count: 300, container: container, now: Fixtures.start, calendar: calendar)
      let context = ModelContext(container)
      let sessions = try context.fetch(FetchDescriptor<WalkingSession>())
      #expect(sessions.count == 300)
      #expect(try context.fetchCount(FetchDescriptor<Segment>()) == 300)
      #expect(try Fixtures.storedPointCount(in: container) == 0)
      var days: [Date: Int] = [:]
      for session in sessions {
        let end = try #require(session.endDate)
        #expect(session.stateRaw == SessionState.finished.rawValue)
        #expect(session.derivedDataVersion == DerivedDataVersion.current)
        #expect((1000...8000).contains(session.distance))
        #expect(end <= Fixtures.start)
        #expect(end > session.startDate)
        #expect(session.walkingDuration == end.timeIntervalSince(session.startDate))
        #expect(session.pauseDuration == 0)
        #expect(session.interruptionDuration == 0)
        let segment = try #require(session.segments.first)
        #expect(session.segments.count == 1)
        #expect(segment.startDate == session.startDate)
        #expect(segment.endDate == end)
        #expect(segment.endReasonRaw == SegmentEndReason.finished.rawValue)
        #expect(segment.steps == session.steps)
        #expect(segment.points.isEmpty)
        #expect(TimeZone(identifier: session.timeZoneIdentifier) != nil)
        // Placed as Statistics does, every walk is in the morning or evening of a seeded day.
        let localStart = StatisticsEntry(session.listItem(), calendar: calendar).localStart
        let hour = calendar.component(.hour, from: localStart)
        #expect((6..<9).contains(hour) || (17..<20).contains(hour))
        days[calendar.startOfDay(for: localStart), default: 0] += 1
      }
      #expect(days.values.allSatisfy { (1...2).contains($0) })
      #expect(sessions.contains { $0.steps == nil })
      #expect(sessions.contains { $0.steps != nil })
      #expect(sessions.contains { $0.timeZoneIdentifier != calendar.timeZone.identifier })
      #expect(try SessionReader(context: context).sessionIDsNeedingRecompute().isEmpty)
    }

    @Test func seededValuesAndIDsAreDeterministic() throws {
      let first = try ModelContainerFactory.make(inMemory: true)
      let second = try ModelContainerFactory.make(inMemory: true)
      try seed(30, in: first)
      try seed(30, in: second)
      let firstContext = ModelContext(first)
      let secondContext = ModelContext(second)
      let firstReader = SessionReader(context: firstContext)
      let secondReader = SessionReader(context: secondContext)
      let items = try firstReader.finishedSessions()
      #expect(items == (try secondReader.finishedSessions()))
      for item in items {
        #expect(try firstReader.session(id: item.id) == secondReader.session(id: item.id))
      }
      let descriptor = FetchDescriptor<Segment>(sortBy: [SortDescriptor(\.startDate)])
      #expect(
        try firstContext.fetch(descriptor).map(\.id) == secondContext.fetch(descriptor).map(\.id))
    }

    @Test func existingFinishedSessionsAreNotChanged() throws {
      let container = try ModelContainerFactory.make(inMemory: true)
      try seed(5, in: container)
      let before = try SessionReader(context: ModelContext(container)).finishedSessions()
      try seed(30, in: container)
      #expect(try SessionReader(context: ModelContext(container)).finishedSessions() == before)
    }

    @Test func existingUnfinishedSessionPreventsSeeding() async throws {
      let container = try ModelContainerFactory.make(inMemory: true)
      let store = SwiftDataTrackingStore(container: container)
      let id = UUID()
      try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
      try seed(30, in: container)
      let sessions = try ModelContext(container).fetch(FetchDescriptor<WalkingSession>())
      #expect(sessions.map(\.id) == [id])
      #expect(sessions.first?.stateRaw == SessionState.recording.rawValue)
    }

    @Test(arguments: [0, -1])
    func rejectsInvalidCount(count: Int) throws {
      let container = try ModelContainerFactory.make(inMemory: true)
      #expect(throws: DebugSessionSeeder.SeedError.invalidCount) {
        try seed(count, in: container)
      }
    }

    private func seed(_ count: Int, in container: ModelContainer) throws {
      try DebugSessionSeeder.seed(
        count: count, container: container, now: Fixtures.start, calendar: calendar)
    }
  }
#endif
