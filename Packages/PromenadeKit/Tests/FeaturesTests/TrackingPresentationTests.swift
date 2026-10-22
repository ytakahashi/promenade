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
    #expect(presentation.displayedFailure(engine) == nil)

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
    #expect(presentation.displayedFailure(engine) == nil)
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
    #expect(presentation.displayedFailure(engine) == nil)

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

  // MARK: Failures outside dialogs

  @Test func startAndOperationFailuresAreShownWhenNoDialogOwnsThem() {
    engine.startFailure = .sensor
    engine.operationFailure = .persistence
    #expect(presentation.displayedFailure(engine) == .sensor)
    engine.startFailure = nil
    #expect(presentation.displayedFailure(engine) == .persistence)
    presentation.requestPause(engine)
    #expect(presentation.displayedFailure(engine) == nil)
  }
}

@MainActor
private final class TestClock {
  var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
  func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
}
