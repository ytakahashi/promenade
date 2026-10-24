import Domain
import Foundation
import SwiftData
import Testing

@testable import Persistence

// Serialize container construction across suites; concurrent Core Data model setup can crash.
@MainActor
struct SegmentStepsTests {
  @Test func eachClosingTransitionSavesStepsAndFinishTotalsThem() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(1), sessionID: id)
    try await store.splitSegment(
      sessionID: id, closingAt: Fixtures.date(1), reason: .signalGap, steps: 10,
      nextStart: Fixtures.date(100))
    try await store.interruptSegment(sessionID: id, at: Fixtures.date(100), steps: 20)
    try await store.openSegment(sessionID: id, at: Fixtures.date(200))
    try await store.pause(sessionID: id, at: Fixtures.date(300), steps: 30)
    try await store.resume(sessionID: id, at: Fixtures.date(400))
    try await store.finish(sessionID: id, at: Fixtures.date(500), steps: 40)
    let record = try Fixtures.record(id, in: container)
    #expect(record.segments.map(\.steps) == [10, 20, 30, 40])
    try Fixtures.read(id, in: container) { #expect($0.steps == 100) }
  }

  @Test func anyUnmeasuredSegmentLeavesSessionStepsUnmeasured() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.splitSegment(
      sessionID: id, closingAt: Fixtures.date(10), reason: .signalGap, steps: nil,
      nextStart: Fixtures.date(100))
    try await store.finish(sessionID: id, at: Fixtures.date(200), steps: 5)
    #expect(try Fixtures.record(id, in: container).segments.map(\.steps) == [nil, 5])
    try Fixtures.read(id, in: container) { #expect($0.steps == nil) }
  }

  @Test func finishWithoutOpenSegmentIgnoresSteps() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.pause(sessionID: id, at: Fixtures.date(10), steps: 7)
    try await store.finish(sessionID: id, at: Fixtures.date(20), steps: 99)
    #expect(try Fixtures.record(id, in: container).segments.map(\.steps) == [7])
    try Fixtures.read(id, in: container) { #expect($0.steps == 7) }
  }

  @Test func pauseAfterAccessLossCountsNoStepsForTheEmptySegment() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.interruptSegment(sessionID: id, at: Fixtures.date(10), steps: 12)
    try await store.pause(sessionID: id, at: Fixtures.date(20), steps: nil)
    try await store.finish(sessionID: id, at: Fixtures.date(30), steps: nil)
    #expect(try Fixtures.record(id, in: container).segments.map(\.steps) == [12, 0])
    try Fixtures.read(id, in: container) { #expect($0.steps == 12) }
  }
}
