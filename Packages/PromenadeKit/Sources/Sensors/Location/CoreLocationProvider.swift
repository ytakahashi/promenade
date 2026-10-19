import CoreLocation
import Domain
import Foundation
import os

public struct CoreLocationProvider: LocationProvider {
  private let makeEvents: @Sendable () -> AsyncThrowingStream<LocationEvent, any Error>

  public init() {
    self.init(
      updates: { CLLocationUpdate.liveUpdates(.fitness) },
      transform: { update in
        let diagnostic = LocationDiagnostics(
          deniedGlobally: update.authorizationDeniedGlobally,
          denied: update.authorizationDenied, restricted: update.authorizationRestricted,
          insufficientlyInUse: update.insufficientlyInUse,
          accuracyLimited: update.accuracyLimited,
          requestInProgress: update.authorizationRequestInProgress,
          serviceSessionRequired: update.serviceSessionRequired)
        if diagnostic.requestInProgress || diagnostic.serviceSessionRequired {
          sensorLogger.debug("Location update is waiting for authorization or a service session")
        }
        if diagnostic.insufficientlyInUse {
          // Should not happen while the location session keeps a background activity session.
          sensorLogger.warning("Location update reports insufficient in-use status")
        }
        return diagnostic.event(
          point: update.location.map { TrackPoint(location: $0) },
          stationary: update.stationary, unavailable: update.locationUnavailable)
      })
  }

  /// Inject the upstream sequence so termination and cancellation use the production bridge in tests.
  init<Updates: AsyncSequence & Sendable>(
    updates: @escaping @Sendable () -> Updates,
    transform: @escaping @Sendable (Updates.Element) -> LocationEvent?
  ) where Updates.Element: Sendable {
    makeEvents = {
      AsyncThrowingStream { continuation in
        let task = Task {
          do {
            for try await update in updates() {
              try Task.checkCancellation()
              if let event = transform(update) { continuation.yield(event) }
            }
            continuation.finish()
          } catch {
            if !(error is CancellationError) {
              sensorLogger.error(
                "Location updates failed: \(String(describing: error), privacy: .private)")
            }
            continuation.finish(throwing: error)
          }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
      }
    }
  }

  public func events() -> AsyncThrowingStream<LocationEvent, any Error> { makeEvents() }
}

private let sensorLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "Promenade", category: "sensors")
