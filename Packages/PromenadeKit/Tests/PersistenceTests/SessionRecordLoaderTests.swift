import Domain
import Foundation
import SwiftData
import Testing

@testable import Persistence

struct SessionRecordLoaderTests {
  @Test func readsSavedPointsAndLaterSaves() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    let store = SwiftDataTrackingStore(container: container)
    let loader = SessionRecordLoader(container: container)
    let id = UUID()
    try await store.createSession(id: id, startDate: Fixtures.start, timeZone: Fixtures.timeZone)
    #expect(try await loader.session(id: id)?.state == .recording)

    try await store.append(Fixtures.point(1), sessionID: id)
    // Pending points are not saved yet, so a reader must not see them.
    #expect(try await loader.session(id: id)?.segments.first?.points.isEmpty == true)

    try await store.finish(sessionID: id, at: Fixtures.date(2), steps: 3)
    let finished = try #require(try await loader.session(id: id))
    #expect(finished.state == .finished)
    #expect(finished.segments.first?.points == [Fixtures.point(1)])
    #expect(finished.segments.first?.steps == 3)
  }

  @Test func missingSessionIsNil() async throws {
    let container = try ModelContainerFactory.make(inMemory: true)
    #expect(try await SessionRecordLoader(container: container).session(id: UUID()) == nil)
  }
}
