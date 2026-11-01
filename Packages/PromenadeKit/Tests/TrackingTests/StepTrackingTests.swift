import Domain
import Foundation
import Testing

@testable import Tracking

@MainActor
struct StepTrackingTests {
  @Test func pauseAndFinishSaveTheClosedSegmentSteps() async throws {
    let h = try TrackingHarness()
    h.pedometer.countSeconds()
    h.session.onActivate = { h.dates.value = date(5) }
    await h.engine.start()
    await h.send(point(6))
    h.engine.requestPause(at: date(20))
    await h.engine.confirmPendingTransition()
    h.session.onActivate = nil
    await h.engine.resume(at: date(30))
    await h.send(point(31))
    h.engine.requestFinish(at: date(40))
    await h.engine.confirmPendingTransition()
    let saved = try await h.record()
    #expect(saved.segments.map(\.steps) == [15, 10])
    #expect(h.pedometer.queries == [date(5)...date(20), date(30)...date(40)])
    #expect(
      SessionMetricsCalculator.metrics(for: saved, filter: .init(), asOf: date(40)).steps == 25)
  }

  @Test func signalGapStepsIncludeTheGapAndAccessLossStepsEndAtTheLastActivity() async throws {
    let h = try TrackingHarness()
    h.pedometer.countSeconds()
    await h.engine.start()
    await h.send(point(1))
    await h.send(point(100))
    await h.send(point(110))
    await h.engine.receive(.accessLost(.denied))
    let saved = try await h.record()
    #expect(saved.segments.map(\.endReason) == [.signalGap, .interrupted])
    // The closed segment still ends at its last point; only its step count covers the gap.
    #expect(saved.segments.map(\.endDate) == [date(1), date(110)])
    #expect(saved.segments.map(\.steps) == [100, 10])
    #expect(h.pedometer.queries == [date(0)...date(100), date(100)...date(110)])
    #expect(h.engine.liveSession?.record.segments.map(\.steps) == [100, 10])
    #expect(h.engine.liveSession?.steps == 110)
    #expect(
      SessionMetricsCalculator.metrics(for: saved, filter: .init(), asOf: date(110)).steps == 110)
  }

  @Test func slowQuerySavesUnmeasuredStepsWithoutBlockingTheTransition() async throws {
    let h = try TrackingHarness(sleep: { _ in })
    h.pedometer.blockQueries()
    await h.engine.start()
    h.engine.requestPause(at: date(20))
    await h.engine.confirmPendingTransition()
    #expect(h.engine.phase == .paused)
    #expect(try await h.record().segments.map(\.steps) == [nil])
  }

  @Test func cancellingRecoveryDuringTheQueryReleasesResourcesWithoutSaving() async throws {
    // The default harness sleep never elapses, so only cancellation can end the blocked query.
    let h = try TrackingHarness()
    h.pedometer.blockQueries()
    let record = try await h.seed()
    h.dates.value = date(100)
    let recovery = try h.recover([record], launch: .background)
    await eventually { h.pedometer.queries.count == 1 }
    recovery.cancel()
    await recovery.value
    #expect(!h.engine.isBusy)
    #expect(h.session.deactivations == 1)
    #expect(h.provider.subscriptions == 0)
    #expect(h.engine.phase == .awaitingRecoveryDecision(lastActivity: date(1)))
    #expect(await !h.store.calls.contains(.split))
    #expect(try await h.store.loadSession(id: record.id) == record)
    #expect(h.engine.operationFailure == nil)
  }

  @Test func cancellingAConfirmationDuringTheQueryKeepsThePendingTransition() async throws {
    let h = try TrackingHarness()
    h.pedometer.blockQueries()
    await h.engine.start()
    h.engine.requestPause(at: date(10))
    let confirmation = Task { await h.engine.confirmPendingTransition() }
    await eventually { h.pedometer.queries.count == 1 }
    confirmation.cancel()
    await confirmation.value
    #expect(!h.engine.isBusy)
    #expect(h.engine.pendingTransition?.kind == .pause)
    #expect(h.engine.phase == .recording(.searching))
    #expect(h.engine.operationFailure == nil)
    #expect(await !h.store.calls.contains(.pause))
  }

  @Test func finishWhilePausedDoesNotQuery() async throws {
    let h = try TrackingHarness()
    h.pedometer.countSeconds()
    await h.engine.start()
    h.engine.requestPause(at: date(10))
    await h.engine.confirmPendingTransition()
    h.engine.requestFinish(at: date(30))
    await h.engine.confirmPendingTransition()
    #expect(h.pedometer.queries == [date(0)...date(10)])
    #expect(try await h.record().segments.map(\.steps) == [10])
  }

  @Test func liveStepsFollowTheOpenSegment() async throws {
    let h = try TrackingHarness()
    h.pedometer.countSeconds()
    await h.engine.start()
    await eventually { h.pedometer.liveStarts == [date(0)] }
    #expect(h.engine.liveSession?.steps == nil)
    h.pedometer.sendLive(7)
    await eventually { h.engine.liveSession?.steps == 7 }

    h.engine.requestPause(at: date(20))
    await h.engine.confirmPendingTransition()
    await eventually { h.pedometer.activeLiveStreams == 0 }
    #expect(h.engine.liveSession?.steps == 20)

    await h.engine.resume(at: date(30))
    await eventually { h.pedometer.liveStarts == [date(0), date(30)] }
    h.pedometer.sendLive(3)
    await eventually { h.engine.liveSession?.steps == 23 }

    // A signal gap closes the segment and subscribes again from the new segment's start.
    await h.send(point(31))
    await h.send(point(100))
    await eventually { h.pedometer.liveStarts == [date(0), date(30), date(100)] }
    #expect(h.engine.liveSession?.steps == nil)
    await eventually { h.pedometer.activeLiveStreams == 1 }

    h.engine.requestFinish(at: date(110))
    await h.engine.confirmPendingTransition()
    await eventually { h.pedometer.activeLiveStreams == 0 }
  }

  @Test func accessLossStopsLiveStepsUntilANewSegmentOpens() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await h.send(point(1))
    await eventually { h.pedometer.activeLiveStreams == 1 }
    await h.engine.receive(.accessLost(.denied))
    await eventually { h.pedometer.activeLiveStreams == 0 }
    await h.send(point(50))
    await eventually { h.pedometer.liveStarts == [date(0), date(50)] }
  }

  @Test func liveSessionTotalsClosedAndLiveSteps() {
    let live = LiveSession(
      record: SessionRecord(
        id: UUID(), startDate: date(0), state: .recording, timeZoneIdentifier: "UTC",
        segments: [SegmentRecord(index: 0, startDate: date(0))]),
      filter: RouteFilter())
    #expect(live.steps == nil)
    live.updateOpenSegmentSteps(5, segmentStart: date(0))
    #expect(live.steps == 5)
    live.close(at: date(10), reason: .signalGap, steps: 8)
    live.open(at: date(20))
    // A late value from the previous segment's subscription is ignored.
    live.updateOpenSegmentSteps(9, segmentStart: date(0))
    #expect(live.openSegmentSteps == nil)
    live.updateOpenSegmentSteps(2, segmentStart: date(20))
    #expect(live.steps == 10)
    live.close(at: date(30), reason: .signalGap, steps: nil)
    live.open(at: date(40))
    live.updateOpenSegmentSteps(1, segmentStart: date(40))
    #expect(live.steps == nil)
  }

  @Test func discardDeletesTheWalkWithoutShowingItAsFinished() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    let id = try #require(h.engine.liveSession?.id)
    await h.send(point(1))
    h.engine.requestFinish(at: date(10))
    await h.engine.discardPendingFinish()
    #expect(h.engine.phase == .idle)
    #expect(h.engine.liveSession == nil)
    #expect(h.engine.pendingTransition == nil)
    #expect(h.engine.lastFinishedSessionID == nil)
    #expect(h.session.deactivations == 1)
    #expect(try await h.store.loadSession(id: id) == nil)
    #expect(await !h.store.calls.contains(.finish))
    await eventually { h.pedometer.activeLiveStreams == 0 }
  }

  @Test func failedDiscardCanBeCancelledToContinueRecording() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    await h.send(point(1))
    await h.store.failNext(.discard)
    h.engine.requestFinish(at: date(10))
    await h.engine.discardPendingFinish()
    #expect(h.engine.pendingTransition != nil)
    #expect(h.engine.operationFailure == .persistence)
    #expect(h.engine.liveSession != nil)
    h.engine.cancelPendingTransition()
    await h.engine.waitForQueuedOperations()
    await h.send(point(20))
    #expect(try await h.record().segments[0].points.count == 2)
  }

  @Test func discardIsIgnoredForAPendingPause() async throws {
    let h = try TrackingHarness()
    await h.engine.start()
    h.engine.requestPause(at: date(10))
    await h.engine.discardPendingFinish()
    #expect(h.engine.pendingTransition != nil)
    #expect(await !h.store.calls.contains(.discard))
  }

  @Test func backgroundResumeSavesStepsOfTheInterruptedSegment() async throws {
    let h = try TrackingHarness()
    h.pedometer.countSeconds()
    let record = try await h.seed()
    h.dates.value = date(100)
    await (try h.recover([record], launch: .background)).value
    let saved = try await h.record()
    #expect(saved.segments.map(\.endReason) == [.interrupted, nil])
    #expect(saved.segments[0].steps == 1)
    await eventually { h.pedometer.liveStarts == [date(100)] }
  }

  @Test func autoFinishSavesStepsOfTheInterruptedSegment() async throws {
    let h = try TrackingHarness()
    h.pedometer.countSeconds()
    let record = try await h.seed()
    h.dates.value = date(7 * 3600)
    await (try h.recover([record], launch: .background)).value
    let saved = try #require(try await h.store.loadSession(id: record.id))
    #expect(saved.state == .finished)
    #expect(saved.segments.map(\.steps) == [1])
    #expect(h.pedometer.liveStarts.isEmpty)
  }

  @Test func foregroundFinishSavesStepsOfTheInterruptedSegment() async throws {
    let h = try TrackingHarness()
    h.pedometer.countSeconds()
    let record = try await h.seed()
    h.dates.value = date(100)
    await (try h.recover([record], launch: .foreground)).value
    #expect(h.pedometer.liveStarts.isEmpty)
    await h.engine.resolveRecovery(.finish)
    #expect(try await h.record().segments.map(\.steps) == [1])
  }

  @Test func surplusSessionsSaveStepsWhenFinished() async throws {
    let h = try TrackingHarness()
    h.pedometer.countSeconds()
    let surplus = try await h.seed(start: 0)
    let latest = try await h.seed(paused: true, start: 1000)
    h.dates.value = date(1100)
    await (try h.recover([surplus, latest], launch: .background)).value
    let saved = try #require(try await h.store.loadSession(id: surplus.id))
    #expect(saved.state == .finished)
    #expect(saved.segments.map(\.steps) == [1])
  }
}
