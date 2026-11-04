import Foundation
import Persistence

/// Shared editing operations and the notification that refreshes saved-walk collections.
struct SessionTrimDependencies {
  let trimmer: any SessionTrimming
  let querySteps: @MainActor (Date, Date) async throws -> Int?
  let saved: @MainActor () -> Void
}
