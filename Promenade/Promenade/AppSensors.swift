import Features
import Foundation
import Sensors

struct AppSensors {
  let provider: any LocationProvider
  let session: any LocationSession
  let authorization: LocationAuthorizationMonitor?
  let pedometer: any PedometerProvider

  /// The pedometer defaults to one that never counts, so environments that do not opt in (tests,
  /// previews) never show the motion permission prompt.
  init(
    provider: any LocationProvider, session: any LocationSession,
    authorization: LocationAuthorizationMonitor?,
    pedometer: any PedometerProvider = InertPedometerProvider()
  ) {
    self.provider = provider
    self.session = session
    self.authorization = authorization
    self.pedometer = pedometer
  }

  static func make(arguments: [String]) throws -> Self {
    #if DEBUG
      let options: ReplayLaunchOptions?
      do {
        options = try ReplayLaunchOptions.parse(arguments)
      } catch {
        throw StartupFailure(kind: .replayArguments, detail: error.localizedDescription)
      }
      if let options {
        let data: Data
        do {
          data = try Data(contentsOf: URL(fileURLWithPath: options.path))
        } catch {
          throw StartupFailure(kind: .replayFile, detail: error.localizedDescription)
        }
        do {
          return Self(
            provider: try ReplayLocationProvider(
              points: GPXParser.parse(data), speedMultiplier: options.speedMultiplier),
            session: ReplayLocationSession(), authorization: nil,
            pedometer: ReplayPedometerProvider(measuresSteps: options.measuresSteps))
        } catch {
          throw StartupFailure(kind: .replayData, detail: error.localizedDescription)
        }
      }
    #endif
    return Self(
      provider: CoreLocationProvider(), session: CoreLocationSession(),
      authorization: LocationAuthorizationMonitor(), pedometer: CoreMotionPedometerProvider())
  }
}

struct StartupFailure: Error, Equatable {
  let kind: StartupFailureKind
  let detail: String
}
