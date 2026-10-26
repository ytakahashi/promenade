import Foundation
import Persistence
import os

/// Refreshes saved metrics without competing with an ongoing recording between sessions.
@MainActor
public final class DerivedDataRefresher {
  private let pendingIDs: @MainActor () throws -> [UUID]
  private let recomputer: any DerivedDataRecomputing
  private let canContinue: @MainActor () -> Bool
  private var hasRun = false

  public init(
    pendingIDs: @escaping @MainActor () throws -> [UUID],
    recomputer: any DerivedDataRecomputing,
    canContinue: @escaping @MainActor () -> Bool
  ) {
    self.pendingIDs = pendingIDs
    self.recomputer = recomputer
    self.canContinue = canContinue
  }

  /// Runs at most once, including attempts interrupted by recording or cancellation.
  public func run() async {
    guard !hasRun else { return }
    // Set before the first suspension so concurrent callers cannot repeat the work.
    hasRun = true
    guard !Task.isCancelled, canContinue() else { return }
    let ids: [UUID]
    do {
      ids = try pendingIDs()
    } catch {
      persistenceLogger.error(
        "Could not load sessions needing recomputation: \(String(describing: error), privacy: .private)"
      )
      return
    }
    for id in ids {
      guard !Task.isCancelled, canContinue() else { return }
      do {
        _ = try await recomputer.recomputeDerivedData(sessionID: id)
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        persistenceLogger.error(
          "Could not recompute session \(id, privacy: .private): \(String(describing: error), privacy: .private)"
        )
      }
    }
  }
}
