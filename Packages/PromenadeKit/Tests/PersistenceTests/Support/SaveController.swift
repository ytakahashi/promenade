import SwiftData
import Synchronization

/// Injects a failure at the actual save boundary while keeping a real SwiftData context.
final class SaveController: Sendable {
  enum Failure: Error { case injected }

  private struct State {
    var count = 0
    var shouldFail = false
    var failsPersistently = false
  }
  private let state = Mutex(State())

  var count: Int { state.withLock { $0.count } }

  func failNext() { state.withLock { $0.shouldFail = true } }

  /// Fails every save until turned off, e.g. to simulate a full disk.
  func setFailsPersistently(_ fails: Bool) { state.withLock { $0.failsPersistently = fails } }

  func save(_ context: ModelContext) throws {
    let shouldFail = state.withLock {
      $0.count += 1
      let fail = $0.shouldFail || $0.failsPersistently
      $0.shouldFail = false
      return fail
    }
    if shouldFail { throw Failure.injected }
    try context.save()
  }
}
