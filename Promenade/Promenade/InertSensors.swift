import Domain
import Foundation
import Persistence
import Sensors

/// A provider whose stream ends immediately, for environments that must never receive locations.
nonisolated struct InertLocationProvider: LocationProvider {
  func events() -> AsyncThrowingStream<LocationEvent, any Error> {
    AsyncThrowingStream { $0.finish() }
  }
}

/// A pedometer that never counts steps and never touches Core Motion.
nonisolated struct InertPedometerProvider: PedometerProvider {
  var access: MotionAccess { .unavailable }
  func steps(from start: Date, to end: Date) async -> Int? { nil }
  func liveSteps(from start: Date) -> AsyncStream<Int> { AsyncStream { $0.finish() } }
}

/// A session that never creates Core Location resources and never grants access.
@MainActor
final class InertLocationSession: LocationSession {
  var canActivateWithoutPrompt: Bool { false }
  func beginActivation() {}
  func activate() async throws -> LocationAccessResult { .denied(.denied) }
  func deactivate() {}
}

extension AppEnvironment {
  /// The environment used while the app hosts unit tests.
  ///
  /// The host app launches before the tests run. It must not open the saved-walk store, create real
  /// location resources, or recover an unfinished walk left on the simulator, which would make
  /// test results depend on the simulator's data and write to it.
  static func unitTestHost() -> AppEnvironment {
    AppEnvironment(
      makeContainer: { try ModelContainerFactory.make(inMemory: true) },
      makeSensors: {
        AppSensors(
          provider: InertLocationProvider(), session: InertLocationSession(), authorization: nil)
      })
  }
}
