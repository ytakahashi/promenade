import Domain
import Foundation
import SwiftData
import Testing

@testable import Persistence

@MainActor
struct MappingAndReaderTests {
  @Test func existingReaderSeesActorStateTransitions() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let reader = SessionReader(context: ModelContext(container))
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    #expect(try reader.unfinishedSession()?.state == .recording)
    try await store.pause(sessionID: id, at: Fixtures.date(10), steps: nil)
    #expect(try reader.session(id: id)?.state == .paused)
    try await store.finish(sessionID: id, at: Fixtures.date(20), steps: nil)
    #expect(try reader.session(id: id)?.state == .finished)
    #expect(try reader.session(id: id)?.endDate == Fixtures.date(20))
    #expect(try reader.unfinishedSession() == nil)
  }

  @Test func mappingSortsRelationshipsAndPreservesAllFields() throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let context = ModelContext(container)
    let id = UUID()
    let session = WalkingSession(
      id: id, startDate: Fixtures.start, stateRaw: "paused", timeZoneIdentifier: "Asia/Tokyo")
    let first = Segment(index: 0, startDate: Fixtures.start)
    first.endDate = Fixtures.date(20)
    first.endReasonRaw = "paused"
    first.steps = 123
    first.points = [
      LocationPoint(point: Fixtures.point(10)), LocationPoint(point: Fixtures.point(0)),
    ]
    let second = Segment(index: 1, startDate: Fixtures.date(50))
    session.segments = [second, first]
    context.insert(session)
    try context.save()
    let reader = SessionReader(context: ModelContext(container))
    let record = try #require(try reader.session(id: id))
    #expect(record.id == id)
    #expect(record.state == .paused)
    #expect(record.timeZoneIdentifier == "Asia/Tokyo")
    #expect(record.segments.map(\.index) == [0, 1])
    #expect(record.segments[0].endDate == Fixtures.date(20))
    #expect(record.segments[0].endReason == .paused)
    #expect(record.segments[0].steps == 123)
    #expect(record.segments[0].points == [Fixtures.point(0), Fixtures.point(10)])
  }

  @Test func unknownRawValuesThrowInsteadOfDefaulting() throws {
    let session = WalkingSession(
      id: UUID(), startDate: Fixtures.start, stateRaw: "unknown", timeZoneIdentifier: "UTC")
    #expect(throws: PersistenceError.invalidStoredValue(field: "stateRaw", value: "unknown")) {
      try session.record()
    }
    let segment = Segment(index: 0, startDate: Fixtures.start)
    segment.endReasonRaw = "unknown"
    #expect(throws: PersistenceError.invalidStoredValue(field: "endReasonRaw", value: "unknown")) {
      try segment.record()
    }
  }

  @Test func readerSelectsNewestUnfinishedAndExposesSurplusWithoutWriting() throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let context = ModelContext(container)
    let oldID = UUID()
    let newestID = UUID()
    for (id, start, state) in [
      (oldID, 0.0, "paused"), (newestID, 20.0, "recording"), (UUID(), 50.0, "finished"),
    ] {
      context.insert(
        WalkingSession(
          id: id, startDate: Fixtures.date(start), stateRaw: state, timeZoneIdentifier: "UTC"))
    }
    try context.save()
    let readingContext = ModelContext(container)
    let reader = SessionReader(context: readingContext)
    #expect(try reader.unfinishedSession()?.id == newestID)
    #expect(try reader.unfinishedSessions().map(\.id) == [newestID, oldID])
    #expect(!readingContext.hasChanges)
    #expect(try reader.session(id: UUID()) == nil)
  }

  @Test func readerWithOnlyFinishedOrNoSessionsReturnsNone() throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let context = ModelContext(container)
    let reader = SessionReader(context: context)
    #expect(try reader.unfinishedSession() == nil)
    context.insert(
      WalkingSession(
        id: UUID(), startDate: Fixtures.start, stateRaw: "finished", timeZoneIdentifier: "UTC"))
    try context.save()
    #expect(try reader.unfinishedSession() == nil)
    #expect(try reader.unfinishedSessions().isEmpty)
  }

  @Test func deletingSessionCascadesToSegmentsAndPoints() throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let context = ModelContext(container)
    let session = WalkingSession(
      id: UUID(), startDate: Fixtures.start, stateRaw: "recording", timeZoneIdentifier: "UTC")
    let segment = Segment(index: 0, startDate: Fixtures.start)
    segment.points = [
      LocationPoint(point: Fixtures.point(0)), LocationPoint(point: Fixtures.point(10)),
    ]
    session.segments = [segment]
    context.insert(session)
    try context.save()
    let readingContext = ModelContext(container)
    #expect(try readingContext.fetchCount(FetchDescriptor<Segment>()) == 1)
    #expect(try readingContext.fetchCount(FetchDescriptor<LocationPoint>()) == 2)
    context.delete(session)
    try context.save()
    let after = ModelContext(container)
    #expect(try after.fetchCount(FetchDescriptor<WalkingSession>()) == 0)
    #expect(try after.fetchCount(FetchDescriptor<Segment>()) == 0)
    #expect(try after.fetchCount(FetchDescriptor<LocationPoint>()) == 0)
  }

  @Test func finishStoresMeasuredStepsAndConfiguredDistance() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let context = ModelContext(container)
    let id = UUID()
    let session = WalkingSession(
      id: id, startDate: Fixtures.start, stateRaw: "recording", timeZoneIdentifier: "UTC")
    let first = Segment(index: 0, startDate: Fixtures.start)
    first.steps = 10
    first.endDate = Fixtures.date(10)
    first.endReasonRaw = "paused"
    first.points = [
      LocationPoint(point: Fixtures.point(0)), LocationPoint(point: Fixtures.point(10, north: 10)),
    ]
    let second = Segment(index: 1, startDate: Fixtures.date(20))
    session.segments = [second, first]
    context.insert(session)
    try context.save()
    var configuration = TrackingConfiguration.default
    configuration.route.maxHorizontalAccuracy = 4
    let store = SwiftDataTrackingStore(container: container, configuration: configuration)
    try await store.finish(sessionID: id, at: Fixtures.date(30), steps: 20)
    try Fixtures.read(id, in: container) {
      #expect($0.steps == 30)
      #expect($0.distance == 0)
      #expect($0.walkingDuration == 20)
      #expect($0.pauseDuration == 10)
    }
  }
}
