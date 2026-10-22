import Domain
import Foundation
import Testing

@testable import Tracking

@MainActor
struct DeferredRecoveryTests {
  @Test(arguments: [false, true])
  func foregroundReleasesSpeculativeResourcesBeforeUserChoice(resumes: Bool) async throws {
    let h = try TrackingHarness()
    let record = try await h.seed()
    h.dates.value = date(100)
    let clock = LaunchTestClock()
    let resolver = pending(clock)
    let recovery = try recover(h, records: [record], resolver: resolver)
    #expect(h.session.begins == 1)
    #expect(h.engine.subscriptionID != nil)
    #expect(h.provider.subscriptions == 0)
    await clock.waitUntilSleeping()
    let duplicate = try recover(h, records: [record], resolver: pending(LaunchTestClock()))
    await duplicate.value
    #expect(h.session.begins == 1)
    #expect(!h.engine.requestPause(at: date(101)))
    #expect(!h.engine.requestFinish(at: date(101)))
    await h.engine.start()
    h.provider.send(.location(point(101), stationary: false))
    await h.engine.flush()
    #expect(await h.store.calls.filter { $0 == .create }.count == 1)
    #expect(try await h.record().segments[0].points.count == 1)
    #expect(h.session.activations == 0)
    resolver.resolve(.foreground)
    await recovery.value
    #expect(h.engine.phase == .awaitingRecoveryDecision(lastActivity: date(1)))
    #expect(h.engine.updatesTask == nil)
    #expect(h.engine.subscriptionID == nil)
    #expect(h.session.deactivations == 1)
    #expect(!h.engine.isBusy)
    await eventually { clock.cancelled }
    await h.engine.resolveRecovery(resumes ? .resume : .finish)
    if resumes {
      await eventually { h.provider.subscriptions == 1 }
      #expect(h.session.activations == 1)
      #expect(h.engine.phase == .recording(.searching))
    } else {
      #expect(h.provider.subscriptions == 0)
      #expect(try await h.record().state == .finished)
    }
  }

  @Test(arguments: [0, 1, 2])
  func deadlineUsesLaunchSnapshotForBackgroundResume(mode: Int) async throws {
    let h = try TrackingHarness()
    let record = try await h.seed(closed: mode == 2)
    let launch = date(mode == 0 ? 61 : 100)
    h.dates.value = launch
    let clock = LaunchTestClock()
    let resolver = pending(clock)
    let recovery = try recover(h, records: [record], resolver: resolver)
    await clock.waitUntilSleeping()
    // Crossing both split and expiry thresholds while waiting must not change the decision.
    h.dates.value = date(30_000)
    clock.advance()
    await recovery.value
    await eventually { h.provider.subscriptions == 1 }
    #expect(h.session.begins == 1)
    #expect(h.session.activations == 1)
    #expect(h.session.deactivations == 0)
    #expect(!resolver.resolve(.foreground))
    let saved = try await h.record()
    #expect(saved.state == .recording)
    #expect(saved.segments.count == (mode == 0 ? 1 : 2))
    if mode != 0 { #expect(saved.segments[1].startDate == launch) }
    h.provider.send(.location(point(30_001), stationary: false))
    await eventually { h.engine.liveSession?.lastPoint?.timestamp == date(30_001) }
  }

  @Test(arguments: [0, 1, 2])
  func launchIndependentRecoveryDoesNotStartTimer(kind: Int) async throws {
    let h = try TrackingHarness()
    let records = kind == 0 ? [] : [try await h.seed(paused: kind == 1)]
    h.dates.value = date(kind == 2 ? 22_000 : 100)
    let clock = LaunchTestClock()
    await (try recover(h, records: records, resolver: pending(clock))).value
    #expect(clock.deadline == nil)
    #expect(h.provider.subscriptions == 0)
    #expect(h.session.begins == (kind == 1 ? 1 : 0))
    switch kind {
    case 0:
      #expect(h.engine.phase == .idle)
      // Completion must release the synchronous reservation even without a record.
      await h.engine.start()
      #expect(h.engine.phase == .recording(.searching))
    case 1: #expect(h.engine.phase == .paused)
    default: #expect(try await h.record().state == .finished)
    }
  }

  @Test(arguments: [false, true])
  func cancellationReleasesReservationAndUnblocksQueue(beforeRunning: Bool) async throws {
    let h = try TrackingHarness()
    let record = try await h.seed()
    h.dates.value = date(100)
    let clock = LaunchTestClock()
    let recovery = try recover(h, records: [record], resolver: pending(clock))
    if !beforeRunning { await clock.waitUntilSleeping() }
    recovery.cancel()
    await recovery.value
    #expect(h.session.deactivations == 1)
    #expect(h.engine.phase == .awaitingRecoveryDecision(lastActivity: date(1)))
    #expect(h.engine.updatesTask == nil)
    #expect(h.provider.subscriptions == 0)
    #expect(!h.engine.isBusy)
    #expect(!h.engine.recoveryScheduled)
    if !beforeRunning { await eventually { clock.cancelled } }
    await h.engine.resolveRecovery(.finish)
    #expect(h.engine.phase == .idle)
  }

  @Test(arguments: [false, true])
  func undecidedLaunchWithoutAccessSkipsSpeculativeReservation(foreground: Bool) async throws {
    let h = try TrackingHarness()
    h.session.canActivateWithoutPrompt = false
    let record = try await h.seed()
    h.dates.value = date(100)
    let clock = LaunchTestClock()
    let resolver = pending(clock)
    let recovery = try recover(h, records: [record], resolver: resolver)
    // Reserving would create a service session, which can prompt before the user's choice.
    #expect(h.session.begins == 0)
    await clock.waitUntilSleeping()
    if foreground {
      resolver.resolve(.foreground)
      await recovery.value
      #expect(h.engine.phase == .awaitingRecoveryDecision(lastActivity: date(1)))
      #expect(h.session.activations == 0)
      // Access is requested only after the user chooses to resume.
      await h.engine.resolveRecovery(.resume)
      #expect(h.session.activations == 1)
    } else {
      clock.advance()
      await recovery.value
      #expect(h.session.activations == 1)
    }
    #expect(h.session.begins == 0)
  }

  @Test func knownBackgroundLaunchReservesEvenWithoutReportedAccess() async throws {
    let h = try TrackingHarness()
    h.session.canActivateWithoutPrompt = false
    let record = try await h.seed()
    h.dates.value = date(100)
    let resolver = LaunchContextResolver(known: .background, reason: .locationOption)
    await (try recover(h, records: [record], resolver: resolver)).value
    #expect(h.session.begins == 1)
  }

  @Test func surplusSessionsFinishOnceAfterResolution() async throws {
    let h = try TrackingHarness()
    let older = try await h.seed()
    let newer = try await h.seed(start: 100)
    h.dates.value = date(200)
    let clock = LaunchTestClock()
    let resolver = pending(clock)
    let recovery = try recover(h, records: [older, newer], resolver: resolver)
    await clock.waitUntilSleeping()
    #expect(await h.store.calls.contains(.finish) == false)
    resolver.resolve(.foreground)
    await recovery.value
    #expect(h.engine.liveSession?.id == newer.id)
    #expect(await h.store.calls.filter { $0 == .finish }.count == 1)
  }

  @Test func fetchFailureDoesNotStartResolutionTimer() throws {
    let h = try TrackingHarness()
    let clock = LaunchTestClock()
    let resolver = pending(clock)
    let coordinator = RecoveryCoordinator(engine: h.engine) {
      throw ControlledStore.Failure.injected
    }
    #expect(throws: ControlledStore.Failure.injected) {
      try coordinator.beginRecovery(resolvingLaunch: resolver)
    }
    #expect(clock.deadline == nil)
    #expect(h.session.begins == 0)
    #expect(!h.engine.recoveryScheduled)
  }

  private func pending(_ clock: LaunchTestClock) -> LaunchContextResolver {
    LaunchContextResolver(timeout: 3, sleepUntil: { try await clock.sleep(until: $0) })
  }

  private func recover(
    _ h: TrackingHarness, records: [SessionRecord], resolver: LaunchContextResolver
  ) throws -> Task<Void, Never> {
    try RecoveryCoordinator(engine: h.engine, dates: h.dates, readUnfinishedSessions: { records })
      .beginRecovery(resolvingLaunch: resolver)
  }
}
