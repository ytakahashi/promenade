import Domain
import Foundation
import Observation
import Tracking

enum TrackingDialog: Equatable {
  case confirmTransition(PendingTransition.Kind)
  /// Finishing a short walk offers discarding it as well as saving it.
  case confirmShortFinish
  /// `isPaused` is the state Cancel keeps: Finish can also be requested while paused.
  case retryTransition(PendingTransition.Kind, isPaused: Bool)
  /// A failed discard is retried as a discard, never as a save.
  case retryDiscard(isPaused: Bool)
  case confirmResume
  case retryResume
}

struct RecoveryDialog: Equatable {
  let lastActivity: Date
  let failure: TrackingFailure?
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
  /// The pending finish judged short when it was requested. Judged once so the dialog does not
  /// change while shown, e.g. when a delayed point raises the distance.
  private(set) var shortFinishTransitionID: UUID?
  /// The pending finish the user chose to discard; a retry after failure discards again.
  private(set) var discardingTransitionID: UUID?
  /// Set before calling the engine: `isBusy` is raised only once the engine's queue runs the call.
  private(set) var isPerforming = false
  /// The finished walk whose summary is shown.
  private(set) var summary: SummaryItem?
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private let shortWalkPolicy: ShortWalkPolicy

  init(now: @escaping () -> Date = Date.init, shortWalkPolicy: ShortWalkPolicy = ShortWalkPolicy())
  {
    self.now = now
    self.shortWalkPolicy = shortWalkPolicy
  }

  func dialog(for engine: some TrackingOperations) -> TrackingDialog? {
    guard !isPerforming else { return nil }
    if let pending = engine.pendingTransition {
      if pending.id == failedTransitionID {
        // A failed transition leaves the phase unchanged, so it is the state Cancel returns to.
        let isPaused = engine.phase == .paused
        return pending.id == discardingTransitionID
          ? .retryDiscard(isPaused: isPaused) : .retryTransition(pending.kind, isPaused: isPaused)
      }
      if pending.id == respondedTransitionID { return nil }
      return pending.id == shortFinishTransitionID
        ? .confirmShortFinish : .confirmTransition(pending.kind)
    }
    guard let resumeRequest else { return nil }
    return resumeRequest.failed ? .retryResume : .confirmResume
  }

  func canOperate(_ engine: some TrackingOperations) -> Bool {
    !isPerforming && !engine.isBusy && engine.pendingTransition == nil && resumeRequest == nil
  }

  /// The launch recovery choice. Ordinary dialogs never coincide with it: they come from a
  /// pending transition or a Resume request, and neither can exist while awaiting this decision.
  func recoveryDialog(for engine: some TrackingOperations) -> RecoveryDialog? {
    guard !isPerforming, case .awaitingRecoveryDecision(let lastActivity) = engine.phase else {
      return nil
    }
    return RecoveryDialog(lastActivity: lastActivity, failure: engine.operationFailure)
  }

  func banner(for engine: some TrackingOperations) -> StatusBannerContent? {
    StatusBannerContent.resolve(
      phase: engine.phase, startFailure: engine.startFailure,
      operationFailure: engine.operationFailure, failureOwnedElsewhere: ownsFailure(engine))
  }

  /// Whether a dialog or an operation in flight accounts for the current failure.
  private func ownsFailure(_ engine: some TrackingOperations) -> Bool {
    if case .awaitingRecoveryDecision = engine.phase { return true }
    return isPerforming || resumeRequest != nil || engine.pendingTransition != nil
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
    guard canOperate(engine), engine.requestFinish(at: now()),
      let pending = engine.pendingTransition,
      let progress = engine.liveProgress(asOf: pending.date)
    else { return }
    // The cutoff is the tap time, so progress up to it matches what Save would store.
    if shortWalkPolicy.isShort(distance: progress.distance, walkingDuration: progress.walking) {
      shortFinishTransitionID = pending.id
    }
  }

  func requestResume(_ engine: some TrackingOperations) {
    guard canOperate(engine), engine.phase == .paused else { return }
    resumeRequest = ResumeRequest(date: now())
  }

  func confirmDialog(_ engine: some TrackingOperations) async {
    if let pending = engine.pendingTransition {
      if pending.id == discardingTransitionID {
        await discardFinish(engine)
      } else {
        await confirmTransition(engine)
      }
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

  /// Discards the walk from the short-walk dialog instead of saving it.
  func discardFinish(_ engine: some TrackingOperations) async {
    guard !isPerforming, let pending = engine.pendingTransition, pending.kind == .finish,
      pending.id == shortFinishTransitionID
    else { return }
    respondedTransitionID = pending.id
    discardingTransitionID = pending.id
    failedTransitionID = nil
    isPerforming = true
    await engine.discardPendingFinish()
    isPerforming = false
    // Like a failed save, a failed discard keeps the transition for a retry or Cancel.
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

  func resolveRecovery(_ choice: RecoveryChoice, _ engine: some TrackingOperations) async {
    guard recoveryDialog(for: engine) != nil else { return }
    isPerforming = true
    await engine.resolveRecovery(choice)
    isPerforming = false
  }

  /// Clears a Start access failure once access is usable again, e.g. after a visit to Settings.
  /// The idle notice prefers that failure while the monitor lags behind it, and only `start()`
  /// would clear it otherwise, so a stale failure would keep Start hidden for good.
  func locationAccessChanged(to access: LocationAccessState, _ engine: some TrackingOperations) {
    guard access == .available || access == .notDetermined,
      engine.phase == .idle, !engine.hasLiveSession,
      engine.startFailure?.isAccess == true
    else { return }
    engine.clearFailure()
  }

  func retry(_ banner: StatusBannerContent, _ engine: some TrackingOperations) async {
    guard !isPerforming else { return }
    isPerforming = true
    defer { isPerforming = false }
    switch banner {
    case .waitingForAccess, .updatesStopped: await engine.retryLocationUpdates()
    case .pointsUnsaved: await engine.flush()
    case .searching, .startFailed, .failed: break
    }
  }

  /// Shows `notice` for as long as `wait` takes, then consumes it. A cancelled wait (the toast
  /// disappeared) keeps the notice so it is presented again rather than lost.
  func presentNotice(
    _ engine: some TrackingOperations, wait: () async throws -> Void
  ) async {
    guard let notice = engine.notice else { return }
    do { try await wait() } catch { return }
    if engine.notice == notice { engine.clearNotice() }
  }

  /// Takes the walk the engine just finished for its summary, once.
  ///
  /// Waits while the engine is busy: launch recovery sets the auto-finish notice only after
  /// finishing, and an auto-finished walk is announced by its toast instead of a summary.
  func consumeFinishedSession(_ engine: some TrackingOperations) {
    guard !engine.isBusy, let id = engine.lastFinishedSessionID else { return }
    if engine.notice != .autoFinished(sessionID: id) { summary = SummaryItem(id: id) }
    // Cleared after taking it so a recreated view does not show the summary again.
    engine.clearLastFinishedSession()
  }

  /// Opens the summary of an auto-finished walk from its toast.
  func showSummary(of notice: TrackingNotice, _ engine: some TrackingOperations) {
    guard case .autoFinished(let id) = notice else { return }
    engine.clearNotice()
    summary = SummaryItem(id: id)
  }

  func dismissSummary() { summary = nil }
}
