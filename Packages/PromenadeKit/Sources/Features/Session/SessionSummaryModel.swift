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
  /// Identifies the latest load, so that a slower earlier read cannot overwrite its result.
  @ObservationIgnored private var latestLoad = 0
  @ObservationIgnored private let read: @MainActor (UUID) async throws -> SessionRecord?
  @ObservationIgnored private let route: RouteFilter.Configuration

  /// - Parameter read: Must not do the reading on the main actor: a long walk holds tens of
  ///   thousands of points.
  init(
    sessionID: UUID, route: RouteFilter.Configuration,
    read: @escaping @MainActor (UUID) async throws -> SessionRecord?
  ) {
    self.sessionID = sessionID
    self.route = route
    self.read = read
  }

  /// Reads the saved walk again. Retrying only reads; the walk is already finished and saved.
  ///
  /// A loaded walk stays on screen during the read, because this runs each time the view appears
  /// and showing progress would discard the map's camera. The read still replaces it, so a walk
  /// deleted on another tab is reported as missing.
  func load() async {
    latestLoad += 1
    let load = latestLoad
    if case .loaded = state {} else { state = .loading }
    let result = await loadedState()
    // A cancelled load belongs to a view that has gone; its next appearance loads again.
    guard load == latestLoad, !Task.isCancelled else { return }
    state = result
  }

  private func loadedState() async -> State {
    do {
      guard let record = try await read(sessionID) else { return .failed(.missing) }
      guard let summary = await Self.makeSummary(record: record, route: route) else {
        return .failed(.unfinished)
      }
      return .loaded(summary)
    } catch {
      return .failed(.readFailed)
    }
  }

  /// Filtering runs over every point of the walk, so it stays off the main actor like the read.
  @concurrent
  private nonisolated static func makeSummary(
    record: SessionRecord, route: RouteFilter.Configuration
  ) async -> SessionSummary? {
    SessionSummary(record: record, route: route)
  }
}
