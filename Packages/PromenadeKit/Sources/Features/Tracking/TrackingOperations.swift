import Domain
import Foundation
import Tracking

/// The engine state and operations the tracking controls use. This narrow seam lets presentation
/// logic be tested without assembling a store and location sensors; the screen still observes the
/// engine directly.
protocol TrackingOperations: AnyObject {
  var phase: TrackingPhase { get }
  var hasLiveSession: Bool { get }
  var pendingTransition: PendingTransition? { get }
  var startFailure: TrackingFailure? { get }
  var operationFailure: TrackingFailure? { get }
  var isBusy: Bool { get }
  var notice: TrackingNotice? { get }
  var lastFinishedSessionID: UUID? { get }
  func start() async
  func requestPause(at date: Date) -> Bool
  func requestFinish(at date: Date) -> Bool
  /// Distance and walking time of the live walk as of `date`, or `nil` without a live walk.
  func liveProgress(asOf date: Date) -> (distance: Double, walking: TimeInterval)?
  func confirmPendingTransition() async
  func discardPendingFinish() async
  func cancelPendingTransition()
  func resume(at date: Date) async
  func resolveRecovery(_ choice: RecoveryChoice) async
  func retryLocationUpdates() async
  func flush() async
  func clearFailure()
  func clearNotice()
  func clearLastFinishedSession()
}

extension TrackingEngine: TrackingOperations {
  var hasLiveSession: Bool { liveSession != nil }

  func liveProgress(asOf date: Date) -> (distance: Double, walking: TimeInterval)? {
    guard let liveSession else { return nil }
    return (liveSession.route.distance, liveSession.timing(asOf: date).walking)
  }
}
