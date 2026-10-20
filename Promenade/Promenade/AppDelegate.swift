import Domain
import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
  let environment: AppEnvironment
  private let recoversOnLaunch: Bool

  override convenience init() {
    // UI tests launch the app as a separate process without this variable, so they still use
    // the regular environment.
    let hostsUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    self.init(
      environment: hostsUnitTests ? .unitTestHost() : AppEnvironment(),
      recoversOnLaunch: !hostsUnitTests)
  }

  init(environment: AppEnvironment, recoversOnLaunch: Bool = true) {
    self.environment = environment
    self.recoversOnLaunch = recoversOnLaunch
    super.init()
  }

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    if recoversOnLaunch {
      beginRecovery(applicationState: application.applicationState)
    }
    return true
  }

  func beginRecovery(applicationState: UIApplication.State) {
    // Background relaunches have little time: recreate location resources before returning
    // to UIKit. Do not move this call into a Task or a SwiftUI view lifecycle callback.
    environment.beginRecovery(launch: applicationState == .background ? .background : .foreground)
  }
}
