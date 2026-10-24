import Domain
import Foundation
import Testing

@testable import Features
@testable import Tracking

@MainActor
struct TrackingPresentationTests {
  private let engine = FakeTrackingOperations()
  private let clock = TestClock()
  private let presentation: TrackingPresentation

  init() {
    let clock = clock
    presentation = TrackingPresentation(now: { clock.date })
  }

  // MARK: Pause and Finish

  @Test func rejectedRequestShowsNoDialog() {
    engine.acceptsRequests = false
    presentation.requestPause(engine)
    presentation.requestFinish(engine)
    #expect(presentation.dialog(for: engine) == nil)
    #expect(presentation.canOperate(engine))
  }

  @Test func acceptedRequestsUseTheTapTimeAndAskForConfirmation() {
    presentation.requestFinish(engine)
    #expect(engine.calls == [.requestFinish(clock.date)])
    #expect(presentation.dialog(for: engine) == .confirmTransition(.finish))
    #expect(!presentation.canOperate(engine))
  }

  @Test func confirmingHidesTheDialogUntilTheEngineFinishes() async {
    presentation.requestPause(engine)
    engine.holdsOperations = true
    let task = Task.immediate { await presentation.confirmDialog(engine) }
    #expect(presentation.dialog(for: engine) == nil)
    // A second confirmation while the first is in flight must not reach the engine.
    await presentation.confirmDialog(engine)
    engine.release()
    await task.value
    #expect(engine.calls.filter { $0 == .confirm }.count == 1)
    #expect(engine.pendingTransition == nil)
    #expect(presentation.dialog(for: engine) == nil)
  }

  @Test func failedConfirmationRetriesTheSameTransition() async throws {
    presentation.requestPause(engine)
    let pending = try #require(engine.pendingTransition)
    engine.confirmOutcome = .failure
    await presentation.confirmDialog(engine)
    #expect(engine.pendingTransition == pending)
    #expect(presentation.dialog(for: engine) == .retryTransition(.pause, isPaused: false))
    #expect(presentation.banner(for: engine) == nil)

    engine.confirmOutcome = .success
    await presentation.confirmDialog(engine)
    #expect(engine.calls == [.requestPause(clock.date), .confirm, .confirm])
    #expect(engine.phase == .paused)
    #expect(presentation.dialog(for: engine) == nil)
  }

  @Test func failedFinishTellsWhichStateCancelKeeps() async {
    engine.confirmOutcome = .failure
    presentation.requestFinish(engine)
    await presentation.confirmDialog(engine)
    #expect(presentation.dialog(for: engine) == .retryTransition(.finish, isPaused: false))
    presentation.cancelDialog(engine)
    engine.completeCancellation()

    engine.phase = .paused
    presentation.requestFinish(engine)
    await presentation.confirmDialog(engine)
    #expect(presentation.dialog(for: engine) == .retryTransition(.finish, isPaused: true))
  }

  // MARK: Short walks

  @Test(arguments: [(49.9, 600.0), (1000, 59.9)])
  func shortWalkOffersSavingOrDiscarding(distance: Double, walking: TimeInterval) {
    engine.progress = (distance, walking)
    presentation.requestFinish(engine)
    #expect(engine.progressDates == [clock.date])
    #expect(presentation.dialog(for: engine) == .confirmShortFinish)
  }

  @Test func walkAtTheMinimumsIsNotShort() {
    engine.progress = (50, 60)
    presentation.requestFinish(engine)
    #expect(presentation.dialog(for: engine) == .confirmTransition(.finish))
  }

  @Test func shortWalkJudgementUsesTheConfiguredPolicy() {
    var configuration = TrackingConfiguration.default
    configuration.shortWalkMinimumDistance = 2000
    let clock = clock
    let presentation = TrackingPresentation(
      now: { clock.date }, shortWalkPolicy: ShortWalkPolicy(configuration: configuration))
    presentation.requestFinish(engine)
    #expect(presentation.dialog(for: engine) == .confirmShortFinish)
  }

  @Test func shortWalkJudgementIsFixedWhileTheDialogIsShown() {
    engine.progress = (10, 10)
    presentation.requestFinish(engine)
    engine.progress = (1000, 600)
    #expect(presentation.dialog(for: engine) == .confirmShortFinish)
  }

  @Test func pauseIsNeverJudgedShort() {
    engine.progress = (10, 10)
    presentation.requestPause(engine)
    #expect(presentation.dialog(for: engine) == .confirmTransition(.pause))
    #expect(engine.progressDates.isEmpty)
  }

  @Test func savingAShortWalkFinishesIt() async {
    engine.progress = (10, 10)
    presentation.requestFinish(engine)
    await presentation.confirmDialog(engine)
    #expect(engine.calls == [.requestFinish(clock.date), .confirm])
    #expect(engine.pendingTransition == nil)
  }

  @Test func discardingAShortWalkHidesTheDialogWhileInFlight() async {
    engine.progress = (10, 10)
    presentation.requestFinish(engine)
    engine.holdsOperations = true
    let task = Task.immediate { await presentation.discardFinish(engine) }
    #expect(presentation.dialog(for: engine) == nil)
    await presentation.discardFinish(engine)
    engine.release()
    await task.value
    #expect(engine.calls == [.requestFinish(clock.date), .discard])
    #expect(engine.pendingTransition == nil)
    #expect(presentation.dialog(for: engine) == nil)
  }

  @Test func discardIsOnlyOfferedForAShortWalk() async {
    presentation.requestFinish(engine)
    await presentation.discardFinish(engine)
    #expect(!engine.calls.contains(.discard))
    #expect(presentation.dialog(for: engine) == .confirmTransition(.finish))
  }

  @Test func failedDiscardRetriesTheDiscard() async {
    engine.progress = (10, 10)
    engine.discardOutcome = .failure
    presentation.requestFinish(engine)
    await presentation.discardFinish(engine)
    #expect(presentation.dialog(for: engine) == .retryDiscard(isPaused: false))
    #expect(presentation.banner(for: engine) == nil)

    engine.discardOutcome = .success
    await presentation.confirmDialog(engine)
    #expect(engine.calls == [.requestFinish(clock.date), .discard, .discard])
    #expect(!engine.calls.contains(.confirm))
    #expect(presentation.dialog(for: engine) == nil)
  }

  @Test func cancellingAFailedDiscardKeepsTheWalk() async {
    engine.progress = (10, 10)
    engine.discardOutcome = .failure
    engine.phase = .paused
    presentation.requestFinish(engine)
    await presentation.discardFinish(engine)
    #expect(presentation.dialog(for: engine) == .retryDiscard(isPaused: true))
    presentation.cancelDialog(engine)
    #expect(engine.calls.suffix(2) == [.clearFailure, .cancel])
    #expect(presentation.dialog(for: engine) == nil)
    engine.completeCancellation()
    #expect(presentation.canOperate(engine))
  }

  @Test func cancellationDoesNotReshowTheDialogBeforeTheEngineClearsIt() {
    presentation.requestPause(engine)
    presentation.cancelDialog(engine)
    #expect(engine.calls.last == .cancel)
    #expect(engine.pendingTransition != nil)
    #expect(presentation.dialog(for: engine) == nil)
    engine.completeCancellation()
    #expect(presentation.canOperate(engine))
  }

  @Test func cancellingAFailedTransitionClearsItsFailure() async {
    presentation.requestFinish(engine)
    engine.confirmOutcome = .failure
    await presentation.confirmDialog(engine)
    presentation.cancelDialog(engine)
    #expect(engine.calls.suffix(2) == [.clearFailure, .cancel])
    #expect(presentation.dialog(for: engine) == nil)
    engine.completeCancellation()
    #expect(presentation.banner(for: engine) == nil)
  }

  // MARK: Resume

  @Test func resumeKeepsTheFirstTapTime() async {
    engine.phase = .paused
    let tapped = clock.date
    presentation.requestResume(engine)
    #expect(presentation.dialog(for: engine) == .confirmResume)
    clock.advance(30)
    await presentation.confirmDialog(engine)
    #expect(engine.calls == [.resume(tapped)])
    #expect(presentation.resumeRequest == nil)
    #expect(presentation.dialog(for: engine) == nil)
  }

  @Test func cancelledResumeTakesANewTimeOnTheNextTap() async {
    engine.phase = .paused
    presentation.requestResume(engine)
    presentation.cancelDialog(engine)
    #expect(presentation.dialog(for: engine) == nil)
    clock.advance(30)
    presentation.requestResume(engine)
    await presentation.confirmDialog(engine)
    #expect(engine.calls == [.resume(clock.date)])
  }

  @Test func failedResumeRetriesWithTheSameTime() async {
    engine.phase = .paused
    engine.resumeOutcome = .failure
    let tapped = clock.date
    presentation.requestResume(engine)
    await presentation.confirmDialog(engine)
    #expect(presentation.dialog(for: engine) == .retryResume)
    #expect(presentation.banner(for: engine) == nil)

    clock.advance(30)
    engine.resumeOutcome = .success
    await presentation.confirmDialog(engine)
    #expect(engine.calls == [.resume(tapped), .clearFailure, .resume(tapped)])
    #expect(presentation.resumeRequest == nil)
  }

  @Test func cancellingAFailedResumeDiscardsItsTimeAndFailure() async {
    engine.phase = .paused
    engine.resumeOutcome = .failure
    presentation.requestResume(engine)
    await presentation.confirmDialog(engine)
    presentation.cancelDialog(engine)
    #expect(engine.calls.last == .clearFailure)
    #expect(presentation.resumeRequest == nil)
    #expect(presentation.canOperate(engine))
  }

  @Test func resumeDeclinedWithoutFailureIsDiscarded() async {
    engine.phase = .paused
    engine.resumeOutcome = .ignored
    presentation.requestResume(engine)
    await presentation.confirmDialog(engine)
    #expect(presentation.resumeRequest == nil)
    #expect(presentation.dialog(for: engine) == nil)
  }

  @Test func resumeIsOnlyRequestedWhilePaused() {
    presentation.requestResume(engine)
    #expect(presentation.resumeRequest == nil)
  }

  // MARK: Duplicate operations

  @Test func busyEngineRejectsEveryOperation() async {
    engine.isBusy = true
    engine.phase = .idle
    engine.hasLiveSession = false
    await presentation.start(engine)
    presentation.requestPause(engine)
    presentation.requestFinish(engine)
    engine.phase = .paused
    presentation.requestResume(engine)
    #expect(engine.calls.isEmpty)
    #expect(presentation.resumeRequest == nil)
  }

  @Test func startIgnoresTapsWhileInFlight() async {
    engine.phase = .idle
    engine.hasLiveSession = false
    engine.holdsOperations = true
    let task = Task.immediate { await presentation.start(engine) }
    #expect(!presentation.canOperate(engine))
    await presentation.start(engine)
    engine.release()
    await task.value
    #expect(engine.calls == [.start])
    #expect(presentation.canOperate(engine))
  }

  @Test func pendingResumeBlocksOtherOperations() {
    engine.phase = .paused
    presentation.requestResume(engine)
    presentation.requestFinish(engine)
    #expect(engine.calls.isEmpty)
  }

  // MARK: Banners

  @Test func bannerLeavesFailuresOfDialogsToTheDialogs() {
    engine.operationFailure = .persistence
    #expect(presentation.banner(for: engine) == .pointsUnsaved)
    presentation.requestPause(engine)
    #expect(presentation.banner(for: engine) == nil)
  }

  @Test func bannerRetriesAreRoutedByCause() async {
    await presentation.retry(.updatesStopped, engine)
    await presentation.retry(.waitingForAccess(.denied), engine)
    await presentation.retry(.pointsUnsaved, engine)
    await presentation.retry(.searching, engine)
    #expect(engine.calls == [.retryLocationUpdates, .retryLocationUpdates, .flush])
  }

  @Test func bannerRetryIgnoresTapsWhileInFlight() async {
    engine.holdsOperations = true
    let task = Task.immediate { await presentation.retry(.updatesStopped, engine) }
    await presentation.retry(.updatesStopped, engine)
    engine.release()
    await task.value
    #expect(engine.calls == [.retryLocationUpdates])
  }

  // MARK: Location access

  @Test(arguments: [
    (LocationAccessIssue.denied, LocationAccessState.denied),
    (.servicesDisabled, .servicesDisabled),
  ])
  func startReturnsAfterAccessIsAllowedInSettings(
    _ issue: LocationAccessIssue, _ blocked: LocationAccessState
  ) {
    engine.phase = .idle
    engine.hasLiveSession = false
    engine.startFailure = .access(issue)
    #expect(startState(access: blocked) == .hidden)

    presentation.locationAccessChanged(to: .available, engine)
    #expect(engine.calls == [.clearFailure])
    #expect(IdleAccessNotice(access: .available, startFailure: engine.startFailure) == nil)
    #expect(startState(access: .available) == .start)
  }

  @Test func accessFailureIsKeptWhileAccessIsStillBlocked() {
    engine.phase = .idle
    engine.hasLiveSession = false
    engine.startFailure = .access(.denied)
    presentation.locationAccessChanged(to: .denied, engine)
    presentation.locationAccessChanged(to: .fullAccuracyRequired, engine)
    #expect(engine.calls.isEmpty)
  }

  @Test func onlyStartAccessFailuresAreClearedByAccessChanges() {
    engine.phase = .idle
    engine.hasLiveSession = false
    engine.startFailure = .persistence
    presentation.locationAccessChanged(to: .available, engine)
    engine.startFailure = nil
    engine.phase = .recording(.waitingForAccess(.denied))
    engine.hasLiveSession = true
    engine.operationFailure = .access(.denied)
    presentation.locationAccessChanged(to: .available, engine)
    #expect(engine.calls.isEmpty)
  }

  private func startState(access: LocationAccessState) -> TrackingControlState {
    let notice = IdleAccessNotice(access: access, startFailure: engine.startFailure)
    return TrackingControlState(
      phase: engine.phase, hasLiveSession: engine.hasLiveSession,
      startAllowed: notice?.allowsStart ?? true)
  }

  // MARK: Launch recovery

  @Test func recoveryIsAskedOnlyWhileAwaitingADecision() {
    let lastActivity = clock.date
    #expect(presentation.recoveryDialog(for: engine) == nil)
    engine.phase = .awaitingRecoveryDecision(lastActivity: lastActivity)
    engine.operationFailure = .access(.denied)
    #expect(
      presentation.recoveryDialog(for: engine)
        == RecoveryDialog(lastActivity: lastActivity, failure: .access(.denied)))
    #expect(presentation.banner(for: engine) == nil)
    #expect(presentation.dialog(for: engine) == nil)
  }

  @Test func recoveryIsHiddenWhileResolvingAndAskedAgainAfterFailure() async {
    engine.phase = .awaitingRecoveryDecision(lastActivity: clock.date)
    engine.holdsOperations = true
    let task = Task.immediate { await presentation.resolveRecovery(.resume, engine) }
    #expect(presentation.recoveryDialog(for: engine) == nil)
    await presentation.resolveRecovery(.finish, engine)
    engine.operationFailure = .persistence
    engine.release()
    await task.value
    #expect(engine.calls == [.resolveRecovery(.resume)])
    #expect(presentation.recoveryDialog(for: engine)?.failure == .persistence)
  }

  // MARK: Summary

  @Test func finishedWalkOpensItsSummaryOnce() {
    let id = UUID()
    engine.lastFinishedSessionID = id
    presentation.consumeFinishedSession(engine)
    presentation.consumeFinishedSession(engine)
    #expect(presentation.summary == SummaryItem(id: id))
    #expect(engine.calls == [.clearLastFinishedSession])
    presentation.dismissSummary()
    #expect(presentation.summary == nil)
  }

  @Test func finishedWalkWaitsUntilTheEngineIsIdle() {
    engine.lastFinishedSessionID = UUID()
    engine.isBusy = true
    presentation.consumeFinishedSession(engine)
    #expect(presentation.summary == nil)
    #expect(engine.calls.isEmpty)
  }

  @Test func autoFinishedWalkIsOpenedOnlyFromItsToast() {
    let id = UUID()
    engine.lastFinishedSessionID = id
    engine.notice = .autoFinished(sessionID: id)
    presentation.consumeFinishedSession(engine)
    #expect(presentation.summary == nil)
    #expect(engine.lastFinishedSessionID == nil)

    presentation.showSummary(of: .autoFinished(sessionID: id), engine)
    #expect(presentation.summary == SummaryItem(id: id))
    #expect(engine.notice == nil)
  }

  @Test func autoFinishNoticeForAnotherWalkDoesNotHideThisSummary() {
    let id = UUID()
    engine.lastFinishedSessionID = id
    engine.notice = .autoFinished(sessionID: UUID())
    presentation.consumeFinishedSession(engine)
    #expect(presentation.summary == SummaryItem(id: id))
  }

  // MARK: Notices

  @Test func noticeIsConsumedOnceAfterItWasShown() async {
    engine.notice = .autoFinished(sessionID: UUID())
    await presentation.presentNotice(engine) {}
    await presentation.presentNotice(engine) {}
    #expect(engine.calls == [.clearNotice])
  }

  @Test func noticeIsKeptWhenTheToastDisappearsEarly() async {
    engine.notice = .autoFinished(sessionID: UUID())
    await presentation.presentNotice(engine) { throw CancellationError() }
    #expect(engine.notice != nil)
    #expect(engine.calls.isEmpty)
  }

  @Test func aReplacedNoticeIsNotConsumedByTheOldToast() async {
    engine.notice = .autoFinished(sessionID: UUID())
    let replacement = TrackingNotice.autoFinished(sessionID: UUID())
    await presentation.presentNotice(engine) { engine.notice = replacement }
    #expect(engine.notice == replacement)
  }
}

@MainActor
private final class TestClock {
  var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
  func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
}
