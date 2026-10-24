import Foundation
import SwiftData
import Testing

@testable import Persistence

// Serialize container construction across suites; concurrent Core Data model setup can crash.
@MainActor
struct FileStoreTests {
  @Test func reopeningContainerPreservesSessionAndAllowsRecordingToContinue() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "walks.store")
    let id = try await writeInitialSession(to: url)
    let container = try ModelContainerFactory.make(url: url)
    let store = SwiftDataTrackingStore(container: container)
    let restored = try #require(try await store.loadSession(id: id))
    #expect(restored.timeZoneIdentifier == "Asia/Tokyo")
    #expect(restored.segments[0].points == [Fixtures.point(0), Fixtures.point(10, north: 10)])
    try await store.append(Fixtures.point(20, north: 20), sessionID: id)
    try await store.finish(sessionID: id, at: Fixtures.date(30), steps: nil)
    try Fixtures.read(id, in: container) {
      #expect($0.stateRaw == "finished")
      #expect(abs($0.distance - 20) < 1e-6)
      #expect($0.walkingDuration == 30)
      #expect($0.segments[0].points.count == 3)
    }
  }

  private func writeInitialSession(to url: URL) async throws -> UUID {
    let container = try ModelContainerFactory.make(url: url)
    let store = SwiftDataTrackingStore(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    try await store.append(Fixtures.point(0), sessionID: id)
    try await store.append(Fixtures.point(10, north: 10), sessionID: id)
    try await store.flush()
    return id
  }
}
