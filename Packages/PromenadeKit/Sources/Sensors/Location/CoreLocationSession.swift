import CoreLocation
import Foundation

@MainActor
protocol LocationSessionResources: AnyObject {
  func accessResult() async throws -> LocationAccessResult
  func invalidate()
}

@MainActor
public final class CoreLocationSession: LocationSession {
  private struct Activation {
    let id: UUID
    let resources: any LocationSessionResources
    let task: Task<LocationAccessResult, any Error>
  }

  private let makeResources: @MainActor () -> any LocationSessionResources
  private let authorizationStatus: @MainActor () -> CLAuthorizationStatus
  private var activation: Activation?

  /// - Parameter fullAccuracyPurposeKey: Must match a key of
  ///   `NSLocationTemporaryUsageDescriptionDictionary` in the app's Info.plist.
  public convenience init(fullAccuracyPurposeKey: String = "RouteRecording") {
    let manager = CLLocationManager()
    self.init(
      makeResources: { CoreLocationSessionResources(purposeKey: fullAccuracyPurposeKey) },
      authorizationStatus: { manager.authorizationStatus })
  }

  init(
    makeResources: @escaping @MainActor () -> any LocationSessionResources,
    authorizationStatus: @escaping @MainActor () -> CLAuthorizationStatus = {
      .authorizedWhenInUse
    }
  ) {
    self.makeResources = makeResources
    self.authorizationStatus = authorizationStatus
  }

  /// A service session created while authorization is undecided can show the permission prompt.
  public var canActivateWithoutPrompt: Bool {
    switch authorizationStatus() {
    case .authorizedWhenInUse, .authorizedAlways: true
    default: false
    }
  }

  public func beginActivation() {
    guard activation == nil else { return }
    // Resource creation must happen before returning to didFinishLaunching during recovery.
    let resources = makeResources()
    let id = UUID()
    let task = Task { [weak self] in
      do {
        try Task.checkCancellation()
        let result = try await resources.accessResult()
        try Task.checkCancellation()
        if result != .granted { self?.endActivation(id: id) }
        return result
      } catch {
        self?.endActivation(id: id)
        throw error
      }
    }
    activation = Activation(id: id, resources: resources, task: task)
  }

  public func activate() async throws -> LocationAccessResult {
    try Task.checkCancellation()
    beginActivation()
    guard let activation else { throw CancellationError() }
    let id = activation.id
    return try await withTaskCancellationHandler {
      let result = try await activation.task.value
      try Task.checkCancellation()
      return result
    } onCancel: {
      Task { @MainActor [weak self] in self?.endActivation(id: id) }
    }
  }

  public func deactivate() {
    guard let id = activation?.id else { return }
    endActivation(id: id)
  }

  private func endActivation(id: UUID) {
    // A late cancellation or diagnostic from a previous activation must not stop its successor.
    guard let current = activation, current.id == id else { return }
    activation = nil
    current.task.cancel()
    current.resources.invalidate()
  }

  isolated deinit {
    activation?.task.cancel()
    activation?.resources.invalidate()
  }
}

@MainActor
private final class CoreLocationSessionResources: NSObject, LocationSessionResources,
  @MainActor CLLocationManagerDelegate
{
  private let background: CLBackgroundActivitySession
  private let service: CLServiceSession
  private let manager = CLLocationManager()
  private let authorizationChanges: AsyncStream<Void>
  private let authorizationContinuation: AsyncStream<Void>.Continuation

  init(purposeKey: String) {
    // Create the background activity session first. During a background relaunch, a service
    // session created without it could report insufficient in-use status.
    background = CLBackgroundActivitySession()
    service = CLServiceSession(authorization: .whenInUse, fullAccuracyPurposeKey: purposeKey)
    // Only the fact that authorization changed matters; the state is read when re-evaluating.
    (authorizationChanges, authorizationContinuation) = AsyncStream.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    super.init()
    // CLLocationManager delivers delegate callbacks on the run loop where it was created (main).
    manager.delegate = self
  }

  func accessResult() async throws -> LocationAccessResult {
    let service = service
    let diagnostics = AsyncThrowingStream<LocationDiagnostics, any Error> { continuation in
      let task = Task { @MainActor in
        do {
          for try await value in service.diagnostics {
            continuation.yield(
              LocationDiagnostics(
                deniedGlobally: value.authorizationDeniedGlobally,
                denied: value.authorizationDenied, restricted: value.authorizationRestricted,
                insufficientlyInUse: value.insufficientlyInUse,
                accuracyLimited: value.fullAccuracyDenied,
                requestInProgress: value.authorizationRequestInProgress,
                serviceSessionRequired: value.serviceSessionRequired))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
    return try await LocationAccessResolver.resolve(
      diagnostics: diagnostics, authorizationChanges: authorizationChanges,
      authorization: { [manager] in (manager.authorizationStatus, manager.accuracyAuthorization) })
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authorizationContinuation.yield()
  }

  func invalidate() {
    manager.delegate = nil
    authorizationContinuation.finish()
    service.invalidate()
    background.invalidate()
  }
}
