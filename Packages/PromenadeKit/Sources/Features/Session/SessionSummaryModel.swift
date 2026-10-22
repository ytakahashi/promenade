import Domain
import Foundation
import Observation

@Observable
final class SessionSummaryModel {
  enum Failure: Equatable {
    case missing
    /// The saved record is not finished yet, so its metrics would not be final.
    case unfinished
    case readFailed
  }

  enum State {
    case loading
    case loaded(SessionSummary)
    case failed(Failure)
  }

  let sessionID: UUID
  private(set) var state = State.loading
  @ObservationIgnored private let read: @MainActor (UUID) throws -> SessionRecord?
  @ObservationIgnored private let route: RouteFilter.Configuration

  init(
    sessionID: UUID, route: RouteFilter.Configuration,
    read: @escaping @MainActor (UUID) throws -> SessionRecord?
  ) {
    self.sessionID = sessionID
    self.route = route
    self.read = read
  }

  /// Reads the saved walk again. Retrying only reads; the walk is already finished and saved.
  func load() {
    state = .loading
    do {
      guard let record = try read(sessionID) else {
        state = .failed(.missing)
        return
      }
      guard let summary = SessionSummary(record: record, route: route) else {
        state = .failed(.unfinished)
        return
      }
      state = .loaded(summary)
    } catch {
      state = .failed(.readFailed)
    }
  }
}
