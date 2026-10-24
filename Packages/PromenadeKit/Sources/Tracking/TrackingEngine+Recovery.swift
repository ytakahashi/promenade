import Domain
import Foundation
import Sensors

// Launch recovery of an unfinished session.
extension TrackingEngine {
  /// The coordinator calls this synchronously during launch, before returning to the OS.
  func beginRecovery(
    sessions: [SessionRecord], resolver: LaunchContextResolver, now: Date
  ) -> Task<Void, Never> {
    guard phase == .idle, !recoveryScheduled, liveSession == nil else {
      return Task {}
    }
    recoveryScheduled = true
    // Report busy from now, not from when the queued work starts: `start()` already rejects taps
    // while recovery is scheduled, and the UI must not offer Start in between. The queued work
    // always runs, even when cancelled, and clears both flags.
    isBusy = true
    let ordered = sessions.filter { $0.state != .finished }.sorted {
      if $0.startDate == $1.startDate { return $0.id.uuidString < $1.id.uuidString }
      return $0.startDate > $1.startDate
    }
    let record = ordered.first
    let policy = RecoveryPolicy(configuration: configuration)
    let foreground = policy.decide(session: record, launch: .foreground, now: now)
    let background = policy.decide(session: record, launch: .background, now: now)
    // Policies independent of launch context must not delay idle, paused, or expired sessions.
    let knownDecision =
      resolver.context.map { $0 == .foreground ? foreground : background }
      ?? (foreground == background ? foreground : nil)
    let provisionalDecision = knownDecision ?? background
    switch provisionalDecision {
    case .restorePaused, .autoResume:
      // While the launch is undecided, the reservation is speculative. Skip it when it could show
      // a permission prompt before the user chooses to resume. Without access, the OS would not
      // have relaunched the app for location, so a background launch loses nothing here.
      if knownDecision == nil && !locationSession.canActivateWithoutPrompt {
        trackingLogger.info(
          "Launch \(resolver.id, privacy: .public): speculative reservation skipped without access")
        break
      }
      // Background launch recovery must recreate resources before this method returns.
      locationSession.beginActivation()
      trackingLogger.info("Launch \(resolver.id, privacy: .public): location resources reserved")
    default: break
    }
    // Even cancellation before task execution must release the resources created above.
    let preparation = queue.submit(runWhenCancelled: true) { [self] in
      isBusy = true
      defer {
        isBusy = false
        recoveryScheduled = false
        syncLiveSteps()
      }
      if let record {
        await recover(
          record, knownDecision: knownDecision, foreground: foreground, background: background,
          resolver: resolver, now: now)
      }
      for surplus in ordered.dropFirst() {
        do {
          if surplus.hasOpenSegment, let open = surplus.segments.last {
            let date = surplus.lastActivityDate
            let steps = try await self.steps(from: open.startDate, to: date)
            try await store.interruptSegment(sessionID: surplus.id, at: date, steps: steps)
          }
          try await store.finish(sessionID: surplus.id, at: surplus.lastActivityDate, steps: nil)
          trackingLogger.warning("Finished a surplus unfinished walking session")
        } catch is CancellationError {
          // Left unfinished; the next launch finishes surplus sessions again.
          break
        } catch { report(error) }
      }
    }
    if case .autoResume = provisionalDecision {
      // Reserve the subscription task synchronously; it cannot consume events before restoration.
      startUpdates(after: preparation, recoveryID: resolver.id)
    }
    return preparation
  }

  private func recover(
    _ record: SessionRecord, knownDecision: RecoveryDecision?, foreground: RecoveryDecision,
    background: RecoveryDecision, resolver: LaunchContextResolver, now: Date
  ) async {
    liveSession = makeLive(record)
    do {
      try Task.checkCancellation()
      let decision: RecoveryDecision
      if let knownDecision {
        decision = knownDecision
      } else {
        decision = try await resolver.wait() == .foreground ? foreground : background
      }
      switch decision {
      case .none: liveSession = nil
      case .askUser(let lastActivity):
        // A speculative background activation must not survive while waiting for user consent.
        if knownDecision == nil {
          stopUpdates()
          locationSession.deactivate()
          trackingLogger.info(
            "Launch \(resolver.id, privacy: .public): speculative location resources released")
        }
        phase = .awaitingRecoveryDecision(lastActivity: lastActivity)
        trackingLogger.info("Launch \(resolver.id, privacy: .public): awaiting recovery decision")
      case .autoFinish(let date):
        phase = .awaitingRecoveryDecision(lastActivity: date)
        try await interruptIfOpen()
        try await finish(at: date)
        notice = .autoFinished(sessionID: record.id)
      case .restorePaused:
        phase = .paused
        _ = try await activate()
      case .autoResume(let mode):
        phase = .recording(.searching)
        if try await activateForRecovery() {
          switch mode {
          case .continueSegment: break
          case .closeAndOpen(let date):
            let steps = try await closingSteps(until: date)
            try await store.splitSegment(
              sessionID: record.id, closingAt: date, reason: .interrupted, steps: steps,
              nextStart: now)
            liveSession?.close(at: date, reason: .interrupted, steps: steps)
            liveSession?.open(at: now)
          case .openNew:
            try await store.openSegment(sessionID: record.id, at: now)
            liveSession?.open(at: now)
          }
          wasStationary = false
        } else {
          try await interruptIfOpen()
          stopUpdates()
        }
      }
    } catch is CancellationError {
      resolver.cancel()
      stopUpdates()
      locationSession.deactivate()
      trackingLogger.info(
        "Launch \(resolver.id, privacy: .public): recovery cancelled and resources released")
      phase =
        record.state == .paused
        ? .paused : .awaitingRecoveryDecision(lastActivity: record.lastActivityDate)
    } catch {
      stopUpdates()
      // A failed recovery must be explicitly retried instead of silently consuming locations
      // against an unprepared segment.
      phase = .awaitingRecoveryDecision(lastActivity: liveSession?.lastActivity ?? now)
      report(error)
    }
  }

  /// Activation for resuming after a background relaunch, bounded by
  /// `configuration.recoveryActivationTimeout`.
  ///
  /// If no definitive result arrives in time, recording proceeds as if access were granted:
  /// waiting indefinitely would leave the relaunched app recording nothing. Real access problems
  /// are still reported by location updates, and a late denial is handled when it arrives.
  private func activateForRecovery() async throws -> Bool {
    let session = locationSession
    // Unstructured so that giving up waiting does not cancel it: cancellation would end the
    // activation and release the background resources.
    let activation = Task { try await session.activate() }
    guard try await completes(activation, within: configuration.recoveryActivationTimeout) else {
      trackingLogger.warning("Location access was not decided in time after relaunch")
      // `beginRecovery` reserves the subscription synchronously for `.autoResume`, so it exists
      // here. Without it, a late denial or failure could not be applied to any subscription.
      guard let id = subscriptionID else {
        trackingLogger.fault("No location subscription to receive a late access result")
        assertionFailure("Recovery resumed without a reserved location subscription")
        return true
      }
      Task { [weak self] in
        do {
          if case .denied(let issue) = try await activation.value {
            await self?.receive(.accessLost(issue), subscription: id)
          }
        } catch is CancellationError {
          // Finishing or retrying may have invalidated this activation.
        } catch {
          // A failed activation releases background resources. Stop the associated subscription
          // so the user can recreate those resources with an explicit retry.
          await self?.streamEnded(id: id, error: error)
        }
      }
      return true
    }
    return try await handleActivation { try await activation.value }
  }

  private func completes(
    _ activation: Task<LocationAccessResult, any Error>, within timeout: TimeInterval
  ) async throws -> Bool {
    let sleep = sleep
    let outcome = RecoveryWaitOutcome()
    let completed = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        outcome.continuation = continuation
        outcome.timer = Task {
          do { try await sleep(timeout) } catch { return }
          outcome.resume(false)
        }
        Task {
          _ = await activation.result
          outcome.resume(true)
        }
      }
    } onCancel: {
      // Timeout preserves activation, but explicit cancellation must release it and unblock the
      // operation queue without waiting for either diagnostics or the timeout.
      activation.cancel()
      // Must hop to the main actor rather than resume directly. For an already-cancelled task,
      // `onCancel` runs before the operation, when no continuation is stored yet. The operation
      // runs synchronously on the main actor and stores the continuation before suspending, so
      // this enqueued resume always finds it.
      Task { @MainActor in outcome.resume(false) }
    }
    try Task.checkCancellation()
    return completed
  }

  public func resolveRecovery(_ choice: RecoveryChoice) async {
    await queue.run { [self] in
      guard case .awaitingRecoveryDecision = phase, let liveSession else { return }
      isBusy = true
      defer {
        isBusy = false
        syncLiveSteps()
      }
      do {
        switch choice {
        case .finish:
          let date = liveSession.lastActivity
          try await interruptIfOpen()
          try await finish(at: date)
        case .resume:
          guard try await activate() else { return }
          let now = max(dates.now(), liveSession.lastActivity)
          if liveSession.record.hasOpenSegment {
            let date = liveSession.lastActivity
            let steps = try await closingSteps(until: date)
            try await store.splitSegment(
              sessionID: liveSession.id, closingAt: date, reason: .interrupted, steps: steps,
              nextStart: now)
            liveSession.close(at: date, reason: .interrupted, steps: steps)
            liveSession.open(at: now)
          } else {
            try await store.openSegment(sessionID: liveSession.id, at: now)
            liveSession.open(at: now)
          }
          phase = .recording(.searching)
          wasStationary = false
          startUpdates()
        }
        clearOperationFailure()
      } catch is CancellationError {
        locationSession.deactivate()
      } catch { report(error) }
    }
  }
}

/// Resumes the waiting continuation once on activation, timeout, or cancellation.
@MainActor
private final class RecoveryWaitOutcome {
  var continuation: CheckedContinuation<Bool, Never>?
  var timer: Task<Void, Never>?

  func resume(_ completed: Bool) {
    guard let continuation else { return }
    self.continuation = nil
    timer?.cancel()
    timer = nil
    continuation.resume(returning: completed)
  }
}
