import Features
import SwiftUI

@main
struct PromenadeApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      AppContentView(environment: delegate.environment)
        .onChange(of: scenePhase, initial: true) { _, phase in
          switch phase {
          case .background: delegate.environment.didEnterBackground()
          case .active: delegate.environment.didBecomeActive()
          default: break
          }
        }
    }
  }
}

private struct AppContentView: View {
  let environment: AppEnvironment

  var body: some View {
    switch environment.state {
    case .waitingForLaunch:
      ProgressView()
    case .failed(let failure):
      StartupFailureView(kind: failure.kind, detail: failure.detail, retry: environment.retry)
    case .ready:
      if let dependencies = environment.dependencies {
        RootView(
          engine: dependencies.engine, configuration: environment.configuration,
          locationAccess: environment.locationAccess, readSession: dependencies.readSession)
      }
    }
  }
}

#if DEBUG
  #Preview {
    AppContentView(environment: .preview())
  }
#endif
