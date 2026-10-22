import Domain
import Tracking

/// Why recording cannot start normally from idle.
enum IdleAccessNotice: Equatable {
  case denied
  case restricted
  case servicesDisabled
  case approximateOnly

  /// Starting can still ask for temporary precise location, so approximate access keeps Start.
  var allowsStart: Bool { self == .approximateOnly }
  /// The app's settings page cannot change restrictions or the device-wide Location Services.
  var opensSettings: Bool { self == .denied || self == .approximateOnly }

  init?(access: LocationAccessState, startFailure: TrackingFailure?) {
    switch access {
    case .denied: self = .denied
    case .restricted: self = .restricted
    case .servicesDisabled: self = .servicesDisabled
    case .fullAccuracyRequired: self = .approximateOnly
    case .notDetermined, .available, .unavailable:
      // The monitor can lag behind the access result Start just received.
      guard case .access(let issue) = startFailure else { return nil }
      self.init(issue: issue)
    }
  }

  init(issue: LocationAccessIssue) {
    switch issue {
    case .denied: self = .denied
    case .servicesDisabled: self = .servicesDisabled
    case .accuracyLimited: self = .approximateOnly
    }
  }
}

enum StatusBannerContent: Equatable {
  case waitingForAccess(LocationAccessIssue)
  /// The location stream ended; `retryLocationUpdates()` restarts it.
  case updatesStopped
  /// Points could not be saved; `flush()` retries them.
  case pointsUnsaved
  case searching
  case startFailed(TrackingFailure)
  case failed(TrackingFailure)

  /// Picks the single most relevant banner.
  ///
  /// - Parameter failureOwnedElsewhere: a dialog is retrying the failed operation, so its failure
  ///   is not repeated here.
  static func resolve(
    phase: TrackingPhase, startFailure: TrackingFailure?, operationFailure: TrackingFailure?,
    failureOwnedElsewhere: Bool
  ) -> Self? {
    if case .recording(.waitingForAccess(let issue)) = phase { return .waitingForAccess(issue) }
    let isRecording = if case .recording = phase { true } else { false }
    let failure = failureOwnedElsewhere ? nil : operationFailure
    if isRecording, failure == .sensor { return .updatesStopped }
    // Transition, Resume, and recovery failures are owned by their dialogs, so a remaining
    // persistence failure while a walk is live comes from saving points.
    if isRecording || phase == .paused, failure == .persistence { return .pointsUnsaved }
    if phase == .recording(.searching) { return .searching }
    if !failureOwnedElsewhere, phase == .idle, let startFailure {
      // Access failures are explained by the idle access notice instead.
      if case .access = startFailure { return nil }
      return .startFailed(startFailure)
    }
    // Access failures accompany the waiting-for-access banner or a dialog.
    if let failure, !failure.isAccess { return .failed(failure) }
    return nil
  }
}

extension TrackingFailure {
  var isAccess: Bool {
    if case .access = self { return true }
    return false
  }
}
