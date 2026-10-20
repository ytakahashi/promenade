#if DEBUG
  import Domain
  import Persistence
  import Sensors

  extension AppEnvironment {
    static func preview() -> AppEnvironment {
      let environment = AppEnvironment(
        makeContainer: { try ModelContainerFactory.make(inMemory: true) },
        makeSensors: {
          AppSensors(
            provider: InertLocationProvider(), session: ReplayLocationSession(),
            authorization: nil)
        })
      environment.beginRecovery(launch: .foreground)
      return environment
    }
  }
#endif
