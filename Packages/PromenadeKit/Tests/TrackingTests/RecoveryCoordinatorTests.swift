import Domain
import Foundation
import Testing

@testable import Tracking

@MainActor
struct RecoveryCoordinatorTests {
  @Test func noUnfinishedSessionDoesNotActivateLocation() async throws {
    let h = try TrackingHarness()
    await (try h.recover([], launch: .foreground)).value
    #expect(h.engine.phase == .idle)
    #expect(h.session.begins == 0)
    #expect(h.session.activations == 0)
  }

  @Test func scheduledRecoveryReportsBusyUntilItCompletes() async throws {
    let h = try TrackingHarness()
    let task = try h.recover([], launch: .foreground)
    // Start is rejected from this point, so the UI must already see the engine as busy.
    #expect(h.engine.isBusy)
    #expect(!h.engine.requestPause(at: date(0)))
    await task.value
    #expect(!h.engine.isBusy)
    await h.engine.start()
    #expect(h.engine.liveSession != nil)
  }

  @Test func pausedRecoveryBeginsSynchronouslyButDoesNotSubscribe() async throws {
    let h = try TrackingHarness()
    let record = try await h.seed(paused: true)
    h.dates.value = date(100)
    let task = try h.recover([record], launch: .background)
    #expect(h.session.begins == 1)
    await task.value
    #expect(h.engine.phase == .paused)
    #expect(h.provider.subscriptions == 0)
    #expect(h.engine.liveSession?.record == record)
    #expect(h.engine.liveSession?.timing(asOf: date(100)).pause == 90)
  }

  @Test(arguments: [false, true])
  func foregroundResumeOrFinishClosesTheOpenSegment(_ resumes: Bool) async throws {
    let h = try TrackingHarness()
    let record = try await h.seed()
    h.dates.value = date(100)
    await (try h.recover([record], launch: .foreground)).value
    #expect(h.session.begins == 0)
    #expect(h.engine.phase == .awaitingRecoveryDecision(lastActivity: date(1)))
    await h.engine.resolveRecovery(resumes ? .resume : .finish)
    let saved = try await h.record()
    #expect(saved.segments[0].endReason == .interrupted)
    #expect(saved.segments[0].endDate == date(1))
    if resumes {
      #expect(saved.segments.count == 2)
      #expect(saved.segments[1].startDate == date(100))
      #expect(h.engine.phase == .recording(.searching))
    } else {
      #expect(saved.segments.count == 1)
      #expect(saved.state == .finished)
      #expect(saved.endDate == date(1))
    }
  }

  @Test(arguments: [false, true])
  func foregroundRecoveryOfClosedSegmentDoesNotCloseItTwice(_ resumes: Bool) async throws {
    let h = try TrackingHarness()
    let record = try await h.seed(closed: true)
    h.dates.value = date(100)
    await (try h.recover([record], launch: .foreground)).value
    await h.engine.resolveRecovery(resumes ? .resume : .finish)
    let saved = try await h.record()
    #expect(saved.segments.count == (resumes ? 2 : 1))
    #expect(saved.segments[0].endDate == record.segments[0].endDate)
    #expect(await h.store.calls.filter { $0 == .interrupt }.count == 1)
  }

  @Test(arguments: [0, 1, 2])
  func backgroundResumeModes(_ mode: Int) async throws {
    let h = try TrackingHarness()
    let record = try await h.seed(closed: mode == 2)
    h.dates.value = date(mode == 0 ? 61 : 100)
    let task = try h.recover([record], launch: .background)
    #expect(h.session.begins == 1)
    await task.value
    await eventually { h.provider.subscriptions == 1 }
    let saved = try await h.record()
    #expect(saved.segments.count == (mode == 0 ? 1 : 2))
    if mode == 1 {
      #expect(saved.segments[0].endReason == .interrupted)
      #expect(saved.segments[0].endDate == date(1))
    }
    if mode != 0 { #expect(saved.segments[1].startDate == date(100)) }
    #expect(h.engine.liveSession?.record == saved)
    #expect(
      h.engine.liveSession?.route.distance
        == RouteFilter().filter(record.segments[0].points).distance)
  }

  @Test func restorationAndActivationFinishBeforeEventsAreConsumed() async throws {
    let h = try TrackingHarness()
    let record = try await h.seed()
    h.dates.value = date(100)
    let gate = TestGate()
    h.session.gate = gate
    let recovery = try h.recover([record], launch: .background)
    #expect(h.session.begins == 1)
    await gate.waitUntilBlocked()
    #expect(h.provider.subscriptions == 0)
    #expect(await h.store.calls.contains(.split) == false)
    await gate.release()
    await recovery.value
    await eventually { h.provider.subscriptions == 1 }
    h.provider.send(.location(point(101), stationary: false))
    await eventually { h.engine.liveSession?.lastPoint?.timestamp == date(101) }
    let saved = try await h.record()
    #expect(saved.segments.count == 2)
    #expect(saved.segments[1].points.map(\.timestamp) == [date(101)])
  }

  @Test(arguments: [false, true])
  func expiredSessionFinishesAtLastActivityWithoutRequestingAccess(_ paused: Bool) async throws {
    let h = try TrackingHarness()
    let record = try await h.seed(paused: paused)
    h.dates.value = date(22_000)
    await (try h.recover([record], launch: .foreground)).value
    let saved = try await h.record()
    #expect(saved.endDate == record.lastActivityDate)
    #expect(saved.state == .finished)
    #expect(saved.segments[0].endReason == (paused ? .paused : .interrupted))
    #expect(h.engine.notice == .autoFinished(sessionID: record.id))
    #expect(h.session.activations == 0)
    h.engine.clearNotice()
    #expect(h.engine.notice == nil)
  }

  @Test func newestSessionIsRestoredAndSurplusSessionsAreFinished() async throws {
    let h = try TrackingHarness()
    let older = try await h.seed()
    let latest = try await h.seed(start: 100)
    h.dates.value = date(200)
    await (try h.recover([older, latest], launch: .foreground)).value
    #expect(h.engine.liveSession?.id == latest.id)
    let savedOlder = try await h.store.loadSession(id: older.id)
    #expect(savedOlder?.state == .finished)
    #expect(savedOlder?.endDate == older.lastActivityDate)
  }

  @Test func failedRecoveryTransitionRequiresExplicitResolution() async throws {
    let h = try TrackingHarness()
    let record = try await h.seed()
    h.dates.value = date(100)
    await h.store.failNext(.split)
    await (try h.recover([record], launch: .background)).value
    #expect(h.engine.phase == .awaitingRecoveryDecision(lastActivity: date(1)))
    #expect(h.engine.operationFailure == .persistence)
    #expect(h.provider.subscriptions == 0)
    await h.engine.resolveRecovery(.resume)
    #expect(try await h.record().segments.count == 2)
  }

  @Test func cancellationBeforeRecoveryRunsReleasesSynchronousResources() async throws {
    let h = try TrackingHarness()
    let record = try await h.seed()
    h.dates.value = date(100)
    let recovery = try h.recover([record], launch: .background)
    #expect(h.session.begins == 1)
    recovery.cancel()
    await recovery.value
    #expect(h.session.deactivations == 1)
    #expect(h.session.activations == 0)
    #expect(h.provider.subscriptions == 0)
    #expect(h.engine.phase == .awaitingRecoveryDecision(lastActivity: date(1)))
    await h.engine.resolveRecovery(.resume)
    #expect(h.engine.phase == .recording(.searching))
  }

  @Test func undecidedAccessAfterRelaunchStartsRecordingAndHandlesLateDenial() async throws {
    // The timeout elapses immediately, while activation stays undecided until released.
    let h = try TrackingHarness(sleep: { _ in })
    let record = try await h.seed()
    h.dates.value = date(100)
    let gate = TestGate()
    h.session.gate = gate
    h.session.result = .denied(.denied)
    await (try h.recover([record], launch: .background)).value
    await eventually { h.provider.subscriptions == 1 }
    #expect(h.engine.phase == .recording(.searching))
    #expect(try await h.record().segments.count == 2)
    await gate.release()
    await eventually { h.engine.phase == .recording(.waitingForAccess(.denied)) }
    // The phase changes before the segment is closed; wait for the late denial to complete.
    await h.engine.waitForQueuedOperations()
    #expect(try await h.record().hasOpenSegment == false)
    #expect(h.session.deactivations == 0)
  }

  @Test func lateActivationFailureStopsUpdatesAndAllowsRetry() async throws {
    let h = try TrackingHarness(sleep: { _ in })
    let record = try await h.seed()
    h.dates.value = date(100)
    let gate = TestGate()
    h.session.gate = gate
    h.session.error = ControlledStore.Failure.injected
    let recovery = try h.recover([record], launch: .background)
    await gate.waitUntilBlocked()
    await recovery.value
    await eventually { h.provider.subscriptions == 1 }
    h.provider.send(.location(point(101), stationary: false))
    await eventually { h.engine.phase == .recording(.active) }

    await gate.release()
    await eventually { h.engine.operationFailure == .sensor }
    #expect(h.engine.phase == .recording(.searching))
    #expect(h.engine.updatesTask == nil)
    #expect(h.engine.subscriptionID == nil)

    h.session.gate = nil
    h.session.error = nil
    await h.engine.retryLocationUpdates()
    await eventually { h.provider.subscriptions == 2 }
    #expect(h.session.activations == 2)
    #expect(h.engine.operationFailure == nil)
    h.provider.send(.location(point(102), stationary: false))
    await eventually { h.engine.liveSession?.lastPoint?.timestamp == date(102) }
  }

  @Test(.timeLimit(.minutes(1)))
  func cancellationWhileAwaitingRecoveryAccessDoesNotWaitForTimeout() async throws {
    let timer = TestGate()
    let h = try TrackingHarness(sleep: { _ in await timer.suspend() })
    let record = try await h.seed()
    h.dates.value = date(100)
    let activation = TestGate()
    h.session.gate = activation
    let recovery = try h.recover([record], launch: .background)
    await activation.waitUntilBlocked()
    await timer.waitUntilBlocked()

    recovery.cancel()
    // Neither dependency has completed: cancellation itself must unblock recovery.
    await eventually { !h.engine.isBusy }
    #expect(h.session.deactivations == 1)
    #expect(h.engine.phase == .awaitingRecoveryDecision(lastActivity: date(1)))
    #expect(h.engine.operationFailure == nil)
    #expect(h.provider.subscriptions == 0)

    await activation.release()
    await timer.release()
    await recovery.value
    h.session.gate = nil
    await h.engine.resolveRecovery(.resume)
    await eventually { h.provider.subscriptions == 1 }
    #expect(h.engine.phase == .recording(.searching))
    #expect(h.engine.operationFailure == nil)
  }

  @Test func deniedBackgroundRecoveryCanRetryAfterAccessIsRestored() async throws {
    let h = try TrackingHarness()
    let record = try await h.seed()
    h.dates.value = date(100)
    h.session.result = .denied(.denied)
    await (try h.recover([record], launch: .background)).value
    #expect(h.engine.phase == .recording(.waitingForAccess(.denied)))
    #expect(h.provider.subscriptions == 0)
    #expect(try await h.record().hasOpenSegment == false)
    h.session.result = .granted
    await h.engine.retryLocationUpdates()
    await eventually { h.provider.subscriptions == 1 }
    h.provider.send(.location(point(101), stationary: false))
    await eventually { h.engine.phase == .recording(.active) }
    #expect(try await h.record().segments.count == 2)
  }
}
