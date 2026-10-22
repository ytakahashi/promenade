import Foundation

@testable import Features
@testable import Tracking

@MainActor
final class FakeTrackingOperations: TrackingOperations {
  enum Call: Equatable {
    case start
    case requestPause(Date)
    case requestFinish(Date)
    case confirm
    case cancel
    case resume(Date)
    case clearFailure
  }

  enum Outcome { case success, failure, ignored }

  var phase: TrackingPhase = .recording(.active)
  var hasLiveSession = true
  var pendingTransition: PendingTransition?
  var startFailure: TrackingFailure?
  var operationFailure: TrackingFailure?
  var isBusy = false
  var acceptsRequests = true
  var confirmOutcome = Outcome.success
  var resumeOutcome = Outcome.success
  /// Suspends async operations until `release()`, to observe state while a call is in flight.
  var holdsOperations = false
  private(set) var calls: [Call] = []
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func start() async {
    calls.append(.start)
    await hold()
  }

  func requestPause(at date: Date) -> Bool {
    calls.append(.requestPause(date))
    return request(.pause, at: date)
  }

  func requestFinish(at date: Date) -> Bool {
    calls.append(.requestFinish(date))
    return request(.finish, at: date)
  }

  func confirmPendingTransition() async {
    calls.append(.confirm)
    await hold()
    switch confirmOutcome {
    case .success:
      phase = pendingTransition?.kind == .pause ? .paused : .idle
      pendingTransition = nil
      operationFailure = nil
    case .failure: operationFailure = .persistence
    case .ignored: break
    }
  }

  /// Like the engine, the pending transition stays until the queued cancellation runs; call
  /// `completeCancellation()` to run it.
  func cancelPendingTransition() { calls.append(.cancel) }

  func completeCancellation() { pendingTransition = nil }

  func resume(at date: Date) async {
    calls.append(.resume(date))
    await hold()
    switch resumeOutcome {
    case .success:
      phase = .recording(.searching)
      operationFailure = nil
    case .failure: operationFailure = .persistence
    case .ignored: break
    }
  }

  func clearFailure() {
    calls.append(.clearFailure)
    startFailure = nil
    operationFailure = nil
  }

  func release() {
    let waiting = waiters
    waiters = []
    for waiter in waiting { waiter.resume() }
  }

  private func request(_ kind: PendingTransition.Kind, at date: Date) -> Bool {
    guard acceptsRequests else { return false }
    pendingTransition = PendingTransition(kind: kind, date: date)
    return true
  }

  private func hold() async {
    guard holdsOperations else { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}
