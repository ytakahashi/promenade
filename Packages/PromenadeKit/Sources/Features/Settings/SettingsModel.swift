import Foundation
import Observation

/// A permission as listed in Settings.
enum PermissionStatus: Equatable {
  case allowed
  case preciseLocationOff
  case denied
  case restricted
  case notDetermined
  case locationServicesOff
  case unavailable

  init(_ access: LocationAccessState) {
    self =
      switch access {
      case .available: .allowed
      case .fullAccuracyRequired: .preciseLocationOff
      case .denied: .denied
      case .restricted: .restricted
      case .notDetermined: .notDetermined
      case .servicesDisabled: .locationServicesOff
      case .unavailable: .unavailable
      }
  }

  init(_ access: MotionAccessState) {
    self =
      switch access {
      case .allowed: .allowed
      case .denied: .denied
      case .restricted: .restricted
      case .notDetermined: .notDetermined
      case .unavailable: .unavailable
      }
  }
}

@Observable
final class SettingsModel {
  /// `Version (Build)`, e.g. "1.0 (12)".
  let version: String
  private(set) var motion: MotionAccessState
  @ObservationIgnored private let motionAccess: @MainActor () -> MotionAccessState

  init(
    infoDictionary: [String: Any]?, motionAccess: @escaping @MainActor () -> MotionAccessState
  ) {
    version = Self.version(infoDictionary: infoDictionary)
    self.motionAccess = motionAccess
    motion = motionAccess()
  }

  /// Motion access has no change notification, so it is read again when Settings appears and
  /// when the app becomes active (e.g. returning from the Settings app).
  func refresh() { motion = motionAccess() }

  static func version(infoDictionary: [String: Any]?) -> String {
    let short = infoDictionary?["CFBundleShortVersionString"] as? String
    let build = infoDictionary?["CFBundleVersion"] as? String
    return switch (short, build) {
    case (let short?, let build?): "\(short) (\(build))"
    case (let short?, nil): short
    case (nil, let build?): build
    case (nil, nil): "--"
    }
  }
}
