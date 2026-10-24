import Domain
import Foundation
import Persistence
import Testing

@testable import Features

@MainActor
struct HistoryModelTests {
  private let deleter = FakeDeleter()

  @Test func loadsSectionsAndReloadsOnEveryCall() {
    let source = ListSource([item(day: 2)])
    let model = HistoryModel(list: source.list, deleter: deleter)
    #expect(model.state == .loading)
    model.load()
    #expect(model.state == .loaded(HistorySection.make(source.items)))
    source.items.append(item(day: 1))
    model.load()
    #expect(model.state == .loaded(HistorySection.make(source.items)))
  }

  @Test func failedReadCanBeRetried() {
    let source = ListSource([])
    source.fails = true
    let model = HistoryModel(list: source.list, deleter: deleter)
    model.load()
    #expect(model.state == .failed)
    source.fails = false
    model.load()
    #expect(model.state == .loaded([]))
  }

  @Test func confirmedDeletionDeletesAndReloads() async {
    let walk = item(day: 1)
    let source = ListSource([walk])
    let model = HistoryModel(list: source.list, deleter: deleter)
    model.load()
    model.requestDelete(walk)
    #expect(model.pendingDeletion == walk)
    source.items = []
    await model.confirmDelete()
    #expect(await deleter.deleted == [walk.id])
    #expect(model.pendingDeletion == nil)
    #expect(model.state == .loaded([]))
    #expect(!model.isDeleting)
  }

  @Test func cancelledDeletionDeletesNothing() async {
    let walk = item(day: 1)
    let model = HistoryModel(list: ListSource([walk]).list, deleter: deleter)
    model.requestDelete(walk)
    model.cancelDelete()
    await model.confirmDelete()
    #expect(await deleter.deleted.isEmpty)
  }

  @Test func failedDeletionKeepsTheListAndReportsUntilDismissed() async {
    let walk = item(day: 1)
    let source = ListSource([walk])
    let model = HistoryModel(list: source.list, deleter: deleter)
    model.load()
    await deleter.setFailure(PersistenceError.sessionNotFinished)
    model.requestDelete(walk)
    await model.confirmDelete()
    #expect(model.deleteFailed)
    #expect(source.reads == 1)
    #expect(model.state == .loaded(HistorySection.make([walk])))
    model.dismissDeleteFailure()
    #expect(!model.deleteFailed)
  }

  private func item(day: Int) -> SessionListItem {
    SessionListItem(
      id: UUID(),
      startDate: Date(timeIntervalSinceReferenceDate: 800_000_000 + Double(day) * 86400),
      timeZoneIdentifier: "Asia/Tokyo", distance: 1000, walkingDuration: 600, steps: 1200)
  }
}

@MainActor
private final class ListSource {
  var items: [SessionListItem]
  var fails = false
  private(set) var reads = 0

  init(_ items: [SessionListItem]) { self.items = items }

  func list() throws -> [SessionListItem] {
    reads += 1
    if fails { throw CocoaError(.fileReadUnknown) }
    return items
  }
}

actor FakeDeleter: SessionDeleting {
  private(set) var deleted: [UUID] = []
  private var failure: (any Error)?

  func setFailure(_ error: any Error) { failure = error }

  func deleteSession(id: UUID) throws {
    if let failure { throw failure }
    deleted.append(id)
  }
}
