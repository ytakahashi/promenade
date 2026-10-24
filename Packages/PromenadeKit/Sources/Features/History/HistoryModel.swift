import Domain
import Foundation
import Observation
import Persistence

@Observable
final class HistoryModel {
  enum State: Equatable {
    case loading
    case loaded([HistorySection])
    case failed
  }

  private(set) var state = State.loading
  /// The walk awaiting delete confirmation.
  private(set) var pendingDeletion: SessionListItem?
  private(set) var deleteFailed = false
  private(set) var isDeleting = false
  @ObservationIgnored private let list: @MainActor () throws -> [SessionListItem]
  @ObservationIgnored private let deleter: any SessionDeleting

  init(list: @escaping @MainActor () throws -> [SessionListItem], deleter: any SessionDeleting) {
    self.list = list
    self.deleter = deleter
  }

  /// Reads the saved walks again. Called whenever History appears, since walks are finished on
  /// another tab.
  func load() {
    do {
      state = .loaded(HistorySection.make(try list()))
    } catch {
      state = .failed
    }
  }

  func requestDelete(_ item: SessionListItem) {
    guard !isDeleting else { return }
    pendingDeletion = item
  }

  func cancelDelete() { pendingDeletion = nil }

  /// The list keeps the walk when deleting fails, and the failure is shown until dismissed.
  func confirmDelete() async {
    guard !isDeleting, let item = pendingDeletion else { return }
    pendingDeletion = nil
    isDeleting = true
    defer { isDeleting = false }
    do {
      try await deleter.deleteSession(id: item.id)
      load()
    } catch {
      deleteFailed = true
    }
  }

  func dismissDeleteFailure() { deleteFailed = false }
}
