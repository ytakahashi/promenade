import Domain
import Foundation
import Sensors

// Location subscription and event handling.
extension TrackingEngine {
  func startUpdates(after preparation: Task<Void, Never>? = nil, recoveryID: UUID? = nil) {
    stopUpdates()
    let id = UUID()
    subscriptionID = id
    let provider = provider
    updatesTask = Task { [weak self] in
      await preparation?.value
      guard !Task.isCancelled, self?.subscriptionID == id,
        case .recording(let status) = self?.phase,
        status == .searching || status == .active
      else { return }
      if let recoveryID {
        trackingLogger.info(
          "Launch \(recoveryID, privacy: .public): subscribing to location updates")
      }
      do {
        for try await event in provider.events() {
          try Task.checkCancellation()
          // Await each event before requesting the next; do not retain the engine while idle.
          await self?.receive(event, subscription: id)
        }
        if !Task.isCancelled { await self?.streamEnded(id: id, error: nil) }
      } catch is CancellationError {
        if !Task.isCancelled { await self?.streamEnded(id: id, error: nil) }
      } catch {
        if !Task.isCancelled { await self?.streamEnded(id: id, error: error) }
      }
    }
  }

  func stopUpdates() {
    subscriptionID = nil
    updatesTask?.cancel()
    updatesTask = nil
  }

  func receive(_ event: LocationEvent, subscription id: UUID) async {
    await queue.submit { [self] in
      guard subscriptionID == id else { return }
      await process(event)
    }.value
  }

  func streamEnded(id: UUID, error: (any Error)?) async {
    await queue.submit { [self] in
      guard subscriptionID == id else { return }
      stopUpdates()
      if case .recording(let status) = phase {
        if case .waitingForAccess = status {} else { phase = .recording(.searching) }
        operationFailure = .sensor
        pointSaveFailed = false
      }
      if let error {
        log(error)
      } else {
        trackingLogger.warning("Location update stream ended unexpectedly")
      }
    }.value
  }

  // Also used by tests to exercise the complete serialized event path without OS delivery timing.
  func receive(_ event: LocationEvent) async {
    await queue.run { [self] in await process(event) }
  }

  func process(_ event: LocationEvent) async {
    guard case .recording = phase, let liveSession else { return }
    if let pending = pendingTransition {
      if case .location(let point, _) = event, point.timestamp <= pending.date {
        // Delayed points preceding the user's tap are still part of the recorded segment.
      } else {
        pendingTransition?.events.append(event)
        return
      }
    }
    switch event {
    case .location(let point, let stationary):
      let segment = liveSession.record.segments.last
      guard isValid(point),
        StoragePointPolicy(configuration: configuration).accepts(
          point, previous: liveSession.lastPoint,
          segmentStart: max(
            segment?.startDate ?? liveSession.record.startDate,
            segment?.endDate ?? liveSession.record.startDate))
      else {
        wasStationary = stationary
        return
      }
      do {
        if case .recording(.waitingForAccess) = phase {
          try await interruptIfOpen()
        }
        if !liveSession.record.hasOpenSegment {
          try await store.openSegment(sessionID: liveSession.id, at: point.timestamp)
          liveSession.open(at: point.timestamp)
          wasStationary = false
        } else if SignalGapPolicy(configuration: configuration).shouldSplit(
          lastPointDate: liveSession.lastPoint?.timestamp, point: point,
          wasStationary: wasStationary)
        {
          let closing = liveSession.lastActivity
          try await store.splitSegment(
            sessionID: liveSession.id, closingAt: closing, reason: .signalGap,
            steps: nil,
            nextStart: point.timestamp)
          liveSession.close(at: closing, reason: .signalGap)
          liveSession.open(at: point.timestamp)
        }
        let result = try await store.append(point, sessionID: liveSession.id)
        liveSession.append(point)
        switch result {
        case .accepted: break
        case .saved: clearPointSaveFailure()
        case .pendingSaveFailure(let error): reportPointSaveFailure(error)
        }
        phase = .recording(.active)
      } catch { report(error) }
      wasStationary = stationary
    case .stationary: wasStationary = true
    case .unavailable:
      if case .recording(.waitingForAccess) = phase {} else { phase = .recording(.searching) }
    case .accessLost(let issue):
      phase = .recording(.waitingForAccess(issue))
      do {
        if liveSession.record.hasOpenSegment {
          try await store.interruptSegment(
            sessionID: liveSession.id, at: liveSession.lastActivity, steps: nil)
          liveSession.close(at: liveSession.lastActivity, reason: .interrupted)
        }
      } catch { report(error) }
    }
  }

  private func isValid(_ point: TrackPoint) -> Bool {
    point.timestamp.timeIntervalSinceReferenceDate.isFinite
      && point.coordinate.latitude.isFinite && point.coordinate.longitude.isFinite
      && (-90...90).contains(point.coordinate.latitude)
      && (-180...180).contains(point.coordinate.longitude)
  }
}
