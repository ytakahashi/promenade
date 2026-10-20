import Features
import Foundation
import Sensors

struct AppSensors {
  let provider: any LocationProvider
  let session: any LocationSession
  let authorization: LocationAuthorizationMonitor?

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
            session: ReplayLocationSession(), authorization: nil)
        } catch {
          throw StartupFailure(kind: .replayData, detail: error.localizedDescription)
        }
      }
    #endif
    return Self(
      provider: CoreLocationProvider(), session: CoreLocationSession(),
      authorization: LocationAuthorizationMonitor())
  }
}

struct StartupFailure: Error, Equatable {
  let kind: StartupFailureKind
  let detail: String
}
