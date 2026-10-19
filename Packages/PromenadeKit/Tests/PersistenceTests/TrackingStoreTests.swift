import Domain
import Foundation
import SwiftData
import Testing

@testable import Persistence

struct TrackingStoreTests {
  @Test func creationIsImmediatelyVisibleToAnotherContext() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    let record = try Fixtures.record(id, in: container)
    #expect(record.id == id)
    #expect(record.startDate == Fixtures.start)
    #expect(record.timeZoneIdentifier == "Asia/Tokyo")
    #expect(record.state == .recording)
    #expect(record.endDate == nil)
    #expect(record.segments == [SegmentRecord(index: 0, startDate: Fixtures.start)])
    try Fixtures.read(id, in: container) {
      #expect($0.derivedDataVersion == 0)
      #expect($0.steps == nil)
    }
  }

  @Test func batchesPointsAndFlushesRemainder() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    for second in 1...9 { try await store.append(Fixtures.point(Double(second)), sessionID: id) }
    #expect(try Fixtures.storedPointCount(in: container) == 0)
    #expect(try await store.loadSession(id: id)?.segments.first?.points.count == 9)
    try await store.append(Fixtures.point(10), sessionID: id)
    #expect(try Fixtures.storedPointCount(in: container) == 10)
    try await store.append(Fixtures.point(11), sessionID: id)
    #expect(try Fixtures.storedPointCount(in: container) == 10)
    try await store.flush()
    #expect(try Fixtures.storedPointCount(in: container) == 11)
  }

  @Test func usesConfiguredBatchSize() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    var configuration = TrackingConfiguration.default
    configuration.saveBatchSize = 2
    let store = SwiftDataTrackingStore(container: container, configuration: configuration)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: id)
    #expect(try Fixtures.storedPointCount(in: container) == 0)
    try await store.append(Fixtures.point(2), sessionID: id)
    #expect(try Fixtures.storedPointCount(in: container) == 2)
  }

  @Test func pauseResumeAndFinishEachSaveOnce() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    #expect(saves.count == 1)
    try await store.append(Fixtures.point(10, north: 10), sessionID: id)
    try await store.pause(sessionID: id, at: Fixtures.date(20))
    #expect(saves.count == 2)
    let paused = try Fixtures.record(id, in: container)
    #expect(paused.state == .paused)
    #expect(paused.segments[0].endReason == .paused)
    #expect(paused.segments[0].endDate == Fixtures.date(20))
    #expect(paused.segments[0].points == [Fixtures.point(10, north: 10)])
    try await store.resume(sessionID: id, at: Fixtures.date(40))
    #expect(saves.count == 3)
    let resumed = try Fixtures.record(id, in: container)
    #expect(resumed.state == .recording)
    #expect(resumed.segments.map(\.index) == [0, 1])
    #expect(resumed.segments[1].startDate == Fixtures.date(40))
    #expect(resumed.hasOpenSegment)
    try await store.finish(sessionID: id, at: Fixtures.date(60))
    #expect(saves.count == 4)
    let finished = try Fixtures.record(id, in: container)
    #expect(finished.state == .finished)
    #expect(finished.endDate == Fixtures.date(60))
    #expect(finished.segments[1].endReason == .finished)
  }

  @Test(arguments: [SegmentEndReason.signalGap, .interrupted])
  func splitClosesAndOpensAtomically(_ reason: SegmentEndReason) async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(10), sessionID: id)
    try await store.splitSegment(
      sessionID: id, closingAt: Fixtures.date(10), reason: reason, nextStart: Fixtures.date(80))
    #expect(saves.count == 2)
    let record = try Fixtures.record(id, in: container)
    #expect(record.state == .recording)
    #expect(record.segments[0].endReason == reason)
    #expect(record.segments[0].endDate == Fixtures.date(10))
    #expect(record.segments[0].points.count == 1)
    #expect(record.segments[1] == SegmentRecord(index: 1, startDate: Fixtures.date(80)))
  }

  @Test func accessLossAndRegainKeepSessionRecording() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(10), sessionID: id)
    try await store.interruptSegment(sessionID: id, at: Fixtures.date(10))
    #expect(saves.count == 2)
    let interrupted = try Fixtures.record(id, in: container)
    #expect(interrupted.state == .recording)
    #expect(!interrupted.hasOpenSegment)
    #expect(interrupted.segments[0].endReason == .interrupted)
    try await store.openSegment(sessionID: id, at: Fixtures.date(50))
    #expect(saves.count == 3)
    #expect(try Fixtures.record(id, in: container).segments[1].startDate == Fixtures.date(50))
  }

  @Test func finishRecomputesFromRawPointsIncludingPendingPointsAfterRecreation() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let id = UUID()
    let first = SwiftDataTrackingStore(container: container)
    try await first.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await first.append(Fixtures.point(0), sessionID: id)
    try await first.append(Fixtures.point(10, north: 10), sessionID: id)
    try await first.splitSegment(
      sessionID: id, closingAt: Fixtures.date(10), reason: .signalGap, nextStart: Fixtures.date(80))
    let store = SwiftDataTrackingStore(container: container)
    try await store.append(Fixtures.point(80, north: 1000), sessionID: id)
    try await store.append(Fixtures.point(90, north: 1020), sessionID: id)
    try await store.finish(sessionID: id, at: Fixtures.date(100))
    try Fixtures.read(id, in: container) {
      #expect(abs($0.distance - 30) < 1e-6)
      #expect($0.walkingDuration == 100)
      #expect($0.pauseDuration == 0)
      #expect($0.interruptionDuration == 0)
      #expect($0.steps == nil)
      #expect($0.derivedDataVersion == DerivedDataVersion.current)
    }
    #expect(try Fixtures.storedPointCount(in: container) == 4)
  }

  @Test(arguments: [SegmentEndReason.paused, .interrupted])
  func finishWhileClosedKeepsReasonAndCountsFinalGap(_ reason: SegmentEndReason) async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    if reason == .paused {
      try await store.pause(sessionID: id, at: Fixtures.date(20))
    } else {
      try await store.interruptSegment(sessionID: id, at: Fixtures.date(20))
    }
    try await store.finish(sessionID: id, at: Fixtures.date(60))
    try Fixtures.read(id, in: container) {
      #expect($0.segments.count == 1)
      #expect($0.segments[0].endReasonRaw == reason.rawValue)
      #expect($0.segments[0].endDate == Fixtures.date(20))
      #expect($0.walkingDuration == 20)
      #expect($0.pauseDuration == (reason == .paused ? 40 : 0))
      #expect($0.interruptionDuration == (reason == .interrupted ? 40 : 0))
    }
  }

  @Test func duplicateAndMissingSessionsThrow() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    #expect(try await store.loadSession(id: id) == nil)
    await #expect(throws: PersistenceError.sessionNotFound(id)) {
      try await store.append(Fixtures.point(1), sessionID: id)
    }
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    await #expect(throws: PersistenceError.duplicateSession(id)) {
      try await store.createSession(
        id: id, startDate: Fixtures.date(10), timeZone: Fixtures.timeZone)
    }
    #expect(try Fixtures.record(id, in: container).startDate == Fixtures.start)
  }

  @Test func invalidTransitionsDoNotMutateSession() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    await #expect(throws: PersistenceError.invalidState) {
      try await store.resume(sessionID: id, at: Fixtures.date(10))
    }
    await #expect(throws: PersistenceError.segmentAlreadyOpen) {
      try await store.openSegment(sessionID: id, at: Fixtures.date(10))
    }
    await #expect(throws: PersistenceError.invalidSplitReason) {
      try await store.splitSegment(
        sessionID: id, closingAt: Fixtures.date(10), reason: .paused, nextStart: Fixtures.date(20))
    }
    try await store.interruptSegment(sessionID: id, at: Fixtures.date(10))
    await #expect(throws: PersistenceError.noOpenSegment) {
      try await store.pause(sessionID: id, at: Fixtures.date(20))
    }
    await #expect(throws: PersistenceError.noOpenSegment) {
      try await store.append(Fixtures.point(20), sessionID: id)
    }
    try await store.finish(sessionID: id, at: Fixtures.date(20))
    await #expect(throws: PersistenceError.invalidState) {
      try await store.openSegment(sessionID: id, at: Fixtures.date(30))
    }
    await #expect(throws: PersistenceError.invalidState) {
      try await store.finish(sessionID: id, at: Fixtures.date(30))
    }
  }

  @Test func rejectsReversedDatesAndPointsWithoutLosingPendingData() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    await #expect(throws: PersistenceError.invalidPointTimestamp) {
      try await store.append(Fixtures.point(-1), sessionID: id)
    }
    try await store.append(Fixtures.point(10), sessionID: id)
    for seconds in [9.0, 10.0] {
      await #expect(throws: PersistenceError.invalidPointTimestamp) {
        try await store.append(Fixtures.point(seconds), sessionID: id)
      }
    }
    await #expect(throws: PersistenceError.invalidDate) {
      try await store.pause(sessionID: id, at: Fixtures.date(9))
    }
    await #expect(throws: PersistenceError.invalidDate) {
      try await store.splitSegment(
        sessionID: id, closingAt: Fixtures.date(10), reason: .signalGap, nextStart: Fixtures.date(9)
      )
    }
    await #expect(throws: PersistenceError.invalidDate) {
      try await store.finish(sessionID: id, at: Fixtures.date(9))
    }
    try await store.pause(sessionID: id, at: Fixtures.date(10))
    await #expect(throws: PersistenceError.invalidDate) {
      try await store.resume(sessionID: id, at: Fixtures.date(9))
    }
    #expect(try Fixtures.record(id, in: container).segments[0].points == [Fixtures.point(10)])
  }
}
