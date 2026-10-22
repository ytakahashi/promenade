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
  func start() async
  func requestPause(at date: Date) -> Bool
  func requestFinish(at date: Date) -> Bool
  func confirmPendingTransition() async
  func cancelPendingTransition()
  func resume(at date: Date) async
  func clearFailure()
}

extension TrackingEngine: TrackingOperations {
  var hasLiveSession: Bool { liveSession != nil }
}
