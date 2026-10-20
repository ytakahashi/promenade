import Domain
import Foundation
import Testing

@testable import Tracking

@MainActor
struct TrackingEngineTests {
  @Test func startPauseResumeFinishPersistsMetricsAndStopsUpdates() async throws {
    let h = try TrackingHarness()
    h.session.onActivate = { h.dates.value = date(5) }
    await h.engine.start()
    #expect(h.engine.liveSession?.record.startDate == date(5))
    await eventually { h.provider.subscriptions == 1 }
    await h.send(point(6))
    await h.send(point(16, north: 0.0001))
    let distance = try #require(h.engine.liveSession?.route.distance)
    #expect(distance > 0)
    h.engine.requestPause(at: date(20))
    await h.engine.confirmPendingTransition()
    #expect(h.engine.phase == .paused)
    #expect(h.session.deactivations == 0)
    await h.send(point(25))
    #expect(try await h.record().segments[0].points.count == 2)
    h.session.onActivate = nil
    await h.engine.resume(at: date(30))
    await h.send(point(31))
    h.engine.requestFinish(at: date(40))
    await h.engine.confirmPendingTransition()
    let saved = try await h.record()
    #expect(saved.state == .finished)
    #expect(saved.endDate == date(40))
    #expect(saved.segments.map(\.endReason) == [.paused, .finished])
    #expect(
      SessionMetricsCalculator.metrics(for: saved, filter: .init(), asOf: date(100)).distance
        == distance)
    #expect(h.engine.phase == .idle)
    #expect(h.engine.liveSession == nil)
    #expect(h.session.deactivations == 1)
  }

  @Test func finishWhilePausedCountsRestUntilFinish() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    h.engine.requestPause(at: date(10))
    await h.engine.confirmPendingTransition()
    h.engine.requestFinish(at: date(30))
    await h.engine.confirmPendingTransition()
    let saved = try await h.record()
    #expect(saved.segments.count == 1)
    #expect(saved.segments[0].endReason == .paused)
    #expect(
      SessionMetricsCalculator.timing(
        segments: saved.segments, sessionStart: saved.startDate, asOf: saved.endDate!
      ).pause == 20)
  }

  @Test func deniedFailedAndCancelledActivationDoNotCreateSessions() async throws {
    for failure in 0..<3 {
      let h = try TrackingHarness()
      if failure == 0 { h.session.result = .denied(.denied) }
      if failure == 1 { h.session.error = ControlledStore.Failure.injected }
      if failure == 2 { h.session.error = CancellationError() }
      await h.engine.start()
      #expect(h.engine.phase == .idle)
      #expect(h.engine.liveSession == nil)
      #expect(await h.store.calls.isEmpty)
      #expect(
        h.engine.startFailure == (failure == 0 ? .access(.denied) : failure == 1 ? .sensor : nil))
    }
  }

  @Test func createFailureReleasesAuthorizationResources() async throws {
    let h = try TrackingHarness()
    await h.store.failNext(.create)
    await h.engine.start()
    #expect(h.engine.startFailure == .persistence)
    #expect(h.engine.phase == .idle)
    #expect(h.session.deactivations == 1)
    await h.engine.start()
    #expect(h.engine.liveSession != nil)
  }

  @Test func confirmationDiscardsLaterPointsAndDiagnosticsButKeepsDelayedPoints() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await h.send(point(1))
    h.engine.requestPause(at: date(10))
    await h.send(point(11))
    await h.engine.receive(.accessLost(.denied))
    await h.send(point(9))
    await h.engine.confirmPendingTransition()
    let saved = try await h.record()
    #expect(saved.segments.count == 1)
    #expect(saved.segments[0].points.map(\.timestamp) == [date(1), date(9)])
    #expect(saved.segments[0].endDate == date(10))
  }

  @Test func cancellationReplaysBufferedEventsInOrderBeforeFollowingCommands() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await h.send(point(1))
    h.engine.requestFinish(at: date(10))
    await h.send(point(11))
    await h.engine.receive(.accessLost(.accuracyLimited))
    await h.send(point(12))
    h.engine.cancelPendingTransition()
    await h.engine.waitForQueuedOperations()
    let saved = try await h.record()
    #expect(saved.state == .recording)
    #expect(saved.segments.count == 2)
    #expect(saved.segments[0].endReason == .interrupted)
    #expect(saved.segments.flatMap(\.points).map(\.timestamp) == [date(1), date(11), date(12)])
  }

  @Test func failedConfirmationKeepsCutoffAndCanBeRetried() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    h.engine.requestPause(at: date(10))
    await h.store.failNext(.pause)
    await h.engine.confirmPendingTransition()
    #expect(h.engine.phase == .recording(.searching))
    #expect(h.engine.pendingTransition?.date == date(10))
    await h.send(point(20))
    await h.engine.confirmPendingTransition()
    #expect(h.engine.phase == .paused)
    #expect(try await h.record().segments[0].points.isEmpty)
  }

  @Test func signalGapStationarityAndInvalidPointHandling() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await h.send(point(1))
    await h.send(point(61))
    #expect(try await h.record().segments.count == 1)
    await h.send(point(122, accuracy: 51))
    #expect(try await h.record().segments.count == 1)
    await h.send(point(123))
    #expect(try await h.record().segments.map(\.endReason) == [.signalGap, nil])
    await h.engine.receive(.stationary)
    await h.send(point(200))
    #expect(try await h.record().segments.count == 2)
    await h.send(point(199))
    await h.send(point(201, north: 100))
    #expect(try await h.record().segments.last?.points.count == 2)
    await h.engine.receive(.unavailable)
    #expect(h.engine.phase == .recording(.searching))
  }

  @Test func accessLossClosesOnceAndInvalidFixDoesNotReopen() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await h.send(point(1))
    await h.engine.receive(.accessLost(.denied))
    await h.engine.receive(.accessLost(.servicesDisabled))
    #expect(h.engine.phase == .recording(.waitingForAccess(.servicesDisabled)))
    await h.send(point(10, accuracy: -1))
    #expect(try await h.record().hasOpenSegment == false)
    await h.send(point(11))
    let saved = try await h.record()
    #expect(saved.segments.count == 2)
    #expect(saved.segments[0].endDate == date(1))
    #expect(saved.segments[1].startDate == date(11))
    #expect(h.engine.phase == .recording(.active))
  }

  @Test func pauseAndFinishRemainAvailableAfterAccessLoss() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await h.send(point(1))
    await h.engine.receive(.accessLost(.denied))
    h.engine.requestPause(at: date(10))
    await h.engine.confirmPendingTransition()
    #expect(h.engine.phase == .paused)
    h.engine.requestFinish(at: date(20))
    await h.engine.confirmPendingTransition()
    #expect(try await h.record().state == .finished)
  }

  @Test func acceptedPointWithSaveFailureStillUpdatesLiveRouteExactlyOnce() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await h.send(point(1))
    await h.store.failAcceptedAppend()
    await h.send(point(11, north: 0.0001))
    #expect(h.engine.operationFailure == .persistence)
    let distance = h.engine.liveSession?.route.distance
    await h.engine.flush()
    let saved = try await h.record()
    #expect(saved.segments[0].points.count == 2)
    #expect(distance == RouteFilter().filter(saved.segments[0].points).distance)
    await h.store.failNext(.append)
    await h.send(point(12))
    #expect(h.engine.liveSession?.record.segments[0].points.count == 2)
  }

  @Test func appendAndPauseCannotOvertakeEachOther() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    let gate = TestGate()
    await h.store.blockNext(.append, on: gate)
    let append = Task { await h.send(point(1)) }
    await gate.waitUntilBlocked()
    h.engine.requestPause(at: date(10))
    let pause = Task { await h.engine.confirmPendingTransition() }
    // Flush deliberately bypasses the queue; it may run now but must not reorder transitions.
    let flush = Task { await h.engine.flush() }
    await Task.yield()
    #expect(await h.store.calls.filter { $0 != .flush } == [.create, .append])
    await gate.release()
    await append.value
    await pause.value
    await flush.value
    #expect(try await h.record().state == .paused)
    #expect(h.engine.liveSession?.record.state == .paused)
  }

  @Test func cancellationDuringStartReleasesResourcesAndAllowsRetry() async throws {
    let h = try TrackingHarness()
    let gate = TestGate()
    h.session.gate = gate
    let start = Task { await h.engine.start() }
    await gate.waitUntilBlocked()
    start.cancel()
    await gate.release()
    await start.value
    #expect(h.engine.phase == .idle)
    #expect(h.engine.startFailure == nil)
    #expect(h.session.deactivations == 1)
    #expect(await h.store.calls.isEmpty)
    h.session.gate = nil
    await h.engine.start()
    #expect(h.engine.liveSession != nil)
  }

  @Test func overlappingStartsCreateOnlyOneSession() async throws {
    let h = try TrackingHarness()
    let gate = TestGate()
    h.session.gate = gate
    let first = Task { await h.engine.start() }
    await gate.waitUntilBlocked()
    let second = Task { await h.engine.start() }
    await gate.release()
    await first.value
    await second.value
    #expect(await h.store.calls.filter { $0 == .create }.count == 1)
    #expect(h.session.activations == 1)
  }

  @Test func finishFailureKeepsRecordingAndSupportsRetry() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await h.send(point(1))
    h.engine.requestFinish(at: date(10))
    await h.store.failNext(.finish)
    await h.engine.confirmPendingTransition()
    #expect(h.engine.lastFinishedSessionID == nil)
    #expect(h.engine.liveSession != nil)
    #expect(h.session.deactivations == 0)
    await h.send(point(11))
    await h.engine.confirmPendingTransition()
    let record = try await h.record()
    #expect(record.endDate == date(10))
    #expect(record.segments[0].points.map(\.timestamp) == [date(1)])
    #expect(h.engine.operationFailure == nil)
  }

  @Test func failedInterruptionIsRetriedBeforeAcceptingTheNextPoint() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await h.send(point(1))
    await h.store.failNext(.interrupt)
    await h.engine.receive(.accessLost(.denied))
    #expect(h.engine.phase == .recording(.waitingForAccess(.denied)))
    await h.send(point(2))
    let record = try await h.record()
    #expect(record.segments.count == 2)
    #expect(record.segments[0].endReason == .interrupted)
    #expect(record.segments[1].points == [point(2)])
  }

  @Test func releasingEngineStopsItsLocationSession() async throws {
    var harness: TrackingHarness? = try TrackingHarness()
    let session = try #require(harness?.session)
    let wasReleased: @MainActor () -> Bool = { [weak engine = harness?.engine] in engine == nil }
    await harness?.engine.start()
    await eventually { harness?.provider.subscriptions == 1 }
    harness = nil
    await eventually(wasReleased)
    #expect(session.deactivations == 1)
  }

  @Test func denialDuringRetryClosesAnOtherwiseOpenSegment() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await eventually { h.provider.subscriptions == 1 }
    await h.send(point(1))
    h.provider.finish()
    await eventually { h.engine.operationFailure == .sensor }
    h.session.result = .denied(.denied)
    await h.engine.retryLocationUpdates()
    let record = try await h.record()
    #expect(record.hasOpenSegment == false)
    #expect(record.segments[0].endDate == date(1))
    #expect(record.segments[0].endReason == .interrupted)
    #expect(h.engine.phase == .recording(.waitingForAccess(.denied)))
  }

  @Test func requestsReportWhetherTheyWereAccepted() async throws {
    let h = try TrackingHarness()
    #expect(!h.engine.requestPause(at: date(1)))
    await h.engine.start()
    await h.send(point(5))
    #expect(!h.engine.requestPause(at: date(4)))
    #expect(h.engine.requestPause(at: date(10)))
    #expect(!h.engine.requestFinish(at: date(11)))
    await h.engine.confirmPendingTransition()
    // While resume waits for access, a request would leave a confirmation dialog with no effect.
    let gate = TestGate()
    h.session.gate = gate
    let resume = Task { await h.engine.resume(at: date(20)) }
    await gate.waitUntilBlocked()
    #expect(h.engine.isBusy)
    #expect(!h.engine.requestFinish(at: date(21)))
    #expect(h.engine.pendingTransition == nil)
    h.session.gate = nil
    await gate.release()
    await resume.value
    #expect(h.engine.requestFinish(at: date(30)))
  }

  @Test(.timeLimit(.minutes(1)))
  func flushIsNotBlockedByAnActivationWaitingForAccess() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await h.send(point(1))
    await h.engine.receive(.accessLost(.denied))
    let gate = TestGate()
    h.session.gate = gate
    let retry = Task { await h.engine.retryLocationUpdates() }
    await gate.waitUntilBlocked()
    await h.engine.flush()
    #expect(await h.store.calls.last == .flush)
    h.session.gate = nil
    await gate.release()
    await retry.value
  }

  @Test func successfulPointSavesClearOnlyPointSaveFailures() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await h.store.failAcceptedAppend()
    await h.send(point(1))
    #expect(h.engine.operationFailure == .persistence)
    await h.store.reportNextAppendSaved()
    await h.send(point(2))
    #expect(h.engine.operationFailure == nil)
    await h.store.failAcceptedAppend()
    await h.send(point(3))
    #expect(h.engine.operationFailure == .persistence)
    await h.engine.flush()
    #expect(h.engine.operationFailure == nil)
    // A failed transition stays visible after later point saves.
    #expect(h.engine.requestPause(at: date(10)))
    await h.store.failNext(.pause)
    await h.engine.confirmPendingTransition()
    #expect(h.engine.operationFailure == .persistence)
    await h.store.reportNextAppendSaved()
    await h.send(point(5))
    await h.engine.flush()
    #expect(h.engine.operationFailure == .persistence)
  }

  @Test func streamCompletionAndFailureExposeSearchingAndAllowResubscription() async throws {
    for fails in [false, true] {
      let h = try TrackingHarness()
      await h.engine.start()
      await eventually { h.provider.subscriptions == 1 }
      h.provider.send(.location(point(1), stationary: false))
      await eventually { h.engine.phase == .recording(.active) }
      h.provider.finish(error: fails ? ControlledStore.Failure.injected : nil)
      await eventually { h.engine.operationFailure == .sensor }
      #expect(h.engine.phase == .recording(.searching))
      await h.engine.retryLocationUpdates()
      await eventually { h.provider.subscriptions == 2 }
      h.provider.send(.location(point(2), stationary: false))
      await eventually { h.engine.liveSession?.lastPoint?.timestamp == date(2) }
    }
  }
}
