import Foundation
import Observation
import Tracking

enum TrackingDialog: Equatable {
  case confirmTransition(PendingTransition.Kind)
  /// `isPaused` is the state Cancel keeps: Finish can also be requested while paused.
  case retryTransition(PendingTransition.Kind, isPaused: Bool)
  case confirmResume
  case retryResume
}

/// Transient UI state around tracking operations. Recording state stays in the engine; dialogs are
/// derived from it on every read so a dismissed or recreated view can never hide a pending
/// transition or clear one on its own.
@Observable
final class TrackingPresentation {
  struct ResumeRequest: Equatable {
    /// The first Resume tap. Retries keep it so the segment starts when the user asked.
    let date: Date
    var failed = false
  }

  private(set) var resumeRequest: ResumeRequest?
  /// The pending transition the user already answered. Cancelling clears the engine's pending
  /// transition later on its queue, and the dialog must not reappear in the meantime.
  private(set) var respondedTransitionID: UUID?
  private(set) var failedTransitionID: UUID?
  /// Set before calling the engine: `isBusy` is raised only once the engine's queue runs the call.
  private(set) var isPerforming = false
  @ObservationIgnored private let now: () -> Date

  init(now: @escaping () -> Date = Date.init) {
    self.now = now
  }

  func dialog(for engine: some TrackingOperations) -> TrackingDialog? {
    guard !isPerforming else { return nil }
    if let pending = engine.pendingTransition {
      if pending.id == failedTransitionID {
        // A failed transition leaves the phase unchanged, so it is the state Cancel returns to.
        return .retryTransition(pending.kind, isPaused: engine.phase == .paused)
      }
      return pending.id == respondedTransitionID ? nil : .confirmTransition(pending.kind)
    }
    guard let resumeRequest else { return nil }
    return resumeRequest.failed ? .retryResume : .confirmResume
  }

  func canOperate(_ engine: some TrackingOperations) -> Bool {
    !isPerforming && !engine.isBusy && engine.pendingTransition == nil && resumeRequest == nil
  }

  /// A failure to show outside dialogs. Failures of an operation being confirmed belong to its
  /// retry dialog and are not repeated.
  func displayedFailure(_ engine: some TrackingOperations) -> TrackingFailure? {
    guard !isPerforming, resumeRequest == nil, engine.pendingTransition == nil else { return nil }
    return engine.startFailure ?? engine.operationFailure
  }

  func start(_ engine: some TrackingOperations) async {
    guard canOperate(engine) else { return }
    isPerforming = true
    await engine.start()
    isPerforming = false
  }

  func requestPause(_ engine: some TrackingOperations) {
    guard canOperate(engine) else { return }
    // A rejected request leaves no pending transition, so no dialog is derived.
    _ = engine.requestPause(at: now())
  }

  func requestFinish(_ engine: some TrackingOperations) {
    guard canOperate(engine) else { return }
    _ = engine.requestFinish(at: now())
  }

  func requestResume(_ engine: some TrackingOperations) {
    guard canOperate(engine), engine.phase == .paused else { return }
    resumeRequest = ResumeRequest(date: now())
  }

  func confirmDialog(_ engine: some TrackingOperations) async {
    if engine.pendingTransition != nil {
      await confirmTransition(engine)
    } else if resumeRequest != nil {
      await confirmResume(engine)
    }
  }

  func cancelDialog(_ engine: some TrackingOperations) {
    guard !isPerforming else { return }
    if let pending = engine.pendingTransition {
      respondedTransitionID = pending.id
      if failedTransitionID == pending.id {
        failedTransitionID = nil
        engine.clearFailure()
      }
      engine.cancelPendingTransition()
    } else if let request = resumeRequest {
      if request.failed { engine.clearFailure() }
      resumeRequest = nil
    }
  }

  private func confirmTransition(_ engine: some TrackingOperations) async {
    guard !isPerforming, let pending = engine.pendingTransition else { return }
    respondedTransitionID = pending.id
    failedTransitionID = nil
    isPerforming = true
    await engine.confirmPendingTransition()
    isPerforming = false
    // The engine keeps a transition whose save failed so the same date can be retried.
    if engine.pendingTransition?.id == pending.id { failedTransitionID = pending.id }
  }

  private func confirmResume(_ engine: some TrackingOperations) async {
    guard !isPerforming, var request = resumeRequest else { return }
    // Clear the previous attempt's failure so a failure after this call is known to be new.
    if request.failed { engine.clearFailure() }
    isPerforming = true
    await engine.resume(at: request.date)
    isPerforming = false
    if engine.phase == .paused, engine.operationFailure != nil {
      request.failed = true
      resumeRequest = request
    } else {
      // Resumed, or the engine declined without a failure (e.g. a cancelled access request).
      resumeRequest = nil
    }
  }
}
