import Foundation
import Testing

@testable import Persistence

// Serialize container construction across suites; concurrent Core Data model setup can crash.
@MainActor
struct SaveFailureTests {
  enum Transition: CaseIterable, Sendable {
    case pause, resume, split, interrupt, open, finish
  }

  @Test(arguments: Transition.allCases)
  func failedTransitionsRollBackAndKeepPendingPoints(_ transition: Transition) async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: id)
    if transition == .resume {
      try await store.pause(sessionID: id, at: Fixtures.date(10))
    } else if transition == .open {
      try await store.interruptSegment(sessionID: id, at: Fixtures.date(10))
    }
    let before = try await store.loadSession(id: id)
    let persistedBefore = try Fixtures.record(id, in: container)
    saves.failNext()
    await #expect(throws: SaveController.Failure.injected) {
      switch transition {
      case .pause: try await store.pause(sessionID: id, at: Fixtures.date(20))
      case .resume: try await store.resume(sessionID: id, at: Fixtures.date(20))
      case .split:
        try await store.splitSegment(
          sessionID: id, closingAt: Fixtures.date(20), reason: .signalGap,
          nextStart: Fixtures.date(30))
      case .interrupt: try await store.interruptSegment(sessionID: id, at: Fixtures.date(20))
      case .open: try await store.openSegment(sessionID: id, at: Fixtures.date(20))
      case .finish: try await store.finish(sessionID: id, at: Fixtures.date(20))
      }
    }
    #expect(try Fixtures.record(id, in: container) == persistedBefore)
    #expect(try await store.loadSession(id: id) == before)
    // Repeated reads must not duplicate replayed points or revive a rolled-back segment.
    #expect(try await store.loadSession(id: id) == before)
    try await store.flush()
    #expect(try Fixtures.record(id, in: container) == before)
    try Fixtures.read(id, in: container) {
      #expect($0.derivedDataVersion == 0)
      #expect($0.endDate == nil)
    }
    // The caller can explicitly retry the failed transition.
    switch transition {
    case .pause: try await store.pause(sessionID: id, at: Fixtures.date(20))
    case .resume: try await store.resume(sessionID: id, at: Fixtures.date(20))
    case .split:
      try await store.splitSegment(
        sessionID: id, closingAt: Fixtures.date(20), reason: .signalGap,
        nextStart: Fixtures.date(30))
    case .interrupt: try await store.interruptSegment(sessionID: id, at: Fixtures.date(20))
    case .open: try await store.openSegment(sessionID: id, at: Fixtures.date(20))
    case .finish: try await store.finish(sessionID: id, at: Fixtures.date(20))
    }
    #expect(try Fixtures.record(id, in: container) != before)
  }

  @Test func failedCreateLeavesNoSessionAndPreservesOtherPendingPoints() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let old = UUID()
    let id = UUID()
    try await store.createSession(id: old, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: old)
    saves.failNext()
    await #expect(throws: SaveController.Failure.injected) {
      try await store.createSession(
        id: id, startDate: Fixtures.date(10), timeZone: Fixtures.timeZone)
    }
    #expect(try await store.loadSession(id: id) == nil)
    try await store.flush()
    #expect(try Fixtures.record(old, in: container).segments[0].points == [Fixtures.point(1)])
    try await store.createSession(id: id, startDate: Fixtures.date(10), timeZone: Fixtures.timeZone)
    #expect(try Fixtures.record(id, in: container).segments.count == 1)
  }

  @Test func failedBatchCanContinueAppendingWithoutLossOrDuplication() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    for second in 1...9 { try await store.append(Fixtures.point(Double(second)), sessionID: id) }
    saves.failNext()
    let result = try await store.append(Fixtures.point(10), sessionID: id)
    guard case .pendingSaveFailure(let error) = result else {
      Issue.record("Expected an accepted point with a pending save failure")
      return
    }
    #expect(error as? SaveController.Failure == .injected)
    #expect(try Fixtures.storedPointCount(in: container) == 0)
    // The next attempt waits for another batch instead of retrying on every append.
    for second in 11...19 { try await store.append(Fixtures.point(Double(second)), sessionID: id) }
    #expect(try Fixtures.storedPointCount(in: container) == 0)
    try await store.append(Fixtures.point(20), sessionID: id)
    #expect(try Fixtures.storedPointCount(in: container) == 20)
    #expect(
      try Fixtures.record(id, in: container).segments[0].points
        == (1...20).map { Fixtures.point(Double($0)) })
    // After a successful save, batching returns to the configured size.
    for second in 21...29 { try await store.append(Fixtures.point(Double(second)), sessionID: id) }
    #expect(try Fixtures.storedPointCount(in: container) == 20)
    try await store.append(Fixtures.point(30), sessionID: id)
    #expect(try Fixtures.storedPointCount(in: container) == 30)
  }

  @Test func persistentFailuresRetryOncePerBatchWithoutReplaying() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    saves.setFailsPersistently(true)
    var failures = 0
    for second in 1...35 {
      if case .pendingSaveFailure(let error) = try await store.append(
        Fixtures.point(Double(second)), sessionID: id)
      {
        #expect(error as? SaveController.Failure == .injected)
        failures += 1
      }
    }
    // One attempt each at 10, 20, and 30 pending points, plus the initial create.
    #expect(failures == 3)
    #expect(saves.count == 4)
    #expect(try await store.loadSession(id: id)?.segments[0].points.count == 35)
    saves.setFailsPersistently(false)
    try await store.flush()
    #expect(
      try Fixtures.record(id, in: container).segments[0].points
        == (1...35).map { Fixtures.point(Double($0)) })
  }

  @Test func transitionFailureAfterPointFailureReplaysUnsavedPoints() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    for second in 1...9 { try await store.append(Fixtures.point(Double(second)), sessionID: id) }
    saves.failNext()
    let result = try await store.append(Fixtures.point(10), sessionID: id)
    guard case .pendingSaveFailure(let error) = result else {
      Issue.record("Expected an accepted point with a pending save failure")
      return
    }
    #expect(error as? SaveController.Failure == .injected)
    // The rollback of the failed pause also discards the unsaved points still in the context.
    saves.failNext()
    await #expect(throws: SaveController.Failure.injected) {
      try await store.pause(sessionID: id, at: Fixtures.date(20))
    }
    try await store.flush()
    let record = try Fixtures.record(id, in: container)
    #expect(record.state == .recording)
    #expect(record.segments[0].points == (1...10).map { Fixtures.point(Double($0)) })
  }

  @Test func pauseAfterAccessLossIsAtomicAndPreservesInterruptionTiming() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: id)
    try await store.interruptSegment(sessionID: id, at: Fixtures.date(1))
    let before = try await store.loadSession(id: id)
    saves.failNext()
    await #expect(throws: SaveController.Failure.injected) {
      try await store.pause(sessionID: id, at: Fixtures.date(10))
    }
    try await store.flush()
    #expect(try await store.loadSession(id: id) == before)
    #expect(try Fixtures.record(id, in: container) == before)
    try await store.pause(sessionID: id, at: Fixtures.date(10))
    let record = try Fixtures.record(id, in: container)
    #expect(record.state == .paused)
    #expect(record.segments.count == 2)
    #expect(record.segments[0].endReason == .interrupted)
    #expect(record.segments[1].startDate == Fixtures.date(10))
    #expect(record.segments[1].endDate == Fixtures.date(10))
    #expect(record.segments[1].endReason == .paused)
  }

  @Test func repeatedFlushFailuresKeepPointsForRetry() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let saves = SaveController()
    let store = SwiftDataTrackingStore(container: container, save: saves.save)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: id)
    for _ in 0..<2 {
      saves.failNext()
      await #expect(throws: SaveController.Failure.injected) { try await store.flush() }
      #expect(try Fixtures.storedPointCount(in: container) == 0)
    }
    try await store.flush()
    #expect(try Fixtures.record(id, in: container).segments[0].points == [Fixtures.point(1)])
  }
}
