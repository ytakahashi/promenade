import Foundation

/// A deadline clock controlled by the test, including cancellation of a suspended sleep.
@MainActor
final class LaunchTestClock {
  private(set) var deadline: ContinuousClock.Instant?
  private(set) var cancelled = false
  private var sleeper: CheckedContinuation<Void, any Error>?
  private var observers: [CheckedContinuation<Void, Never>] = []

  func sleep(until deadline: ContinuousClock.Instant) async throws {
    try Task.checkCancellation()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.deadline = deadline
        sleeper = continuation
        for observer in observers { observer.resume() }
        observers.removeAll()
      }
    } onCancel: {
      Task { @MainActor in
        self.cancelled = true
        self.complete(throwing: CancellationError())
      }
    }
  }

  func waitUntilSleeping() async {
    if deadline == nil { await withCheckedContinuation { observers.append($0) } }
  }

  func advance() { complete() }

  private func complete(throwing error: (any Error)? = nil) {
    let sleeper = sleeper
    self.sleeper = nil
    if let error { sleeper?.resume(throwing: error) } else { sleeper?.resume() }
  }
}
