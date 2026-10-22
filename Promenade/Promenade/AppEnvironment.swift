import Domain
import Features
import Foundation
import Observation
import Persistence
import Sensors
import SwiftData
import Tracking
import os

@MainActor
@Observable
final class AppEnvironment {
  enum State: Equatable {
    case waitingForLaunch
    case ready
    case failed(StartupFailure)
  }

  let configuration: TrackingConfiguration
  private(set) var state: State = .waitingForLaunch
  private(set) var dependencies: AppDependencies?
  @ObservationIgnored private(set) var recoveryTask: Task<Void, Never>?
  @ObservationIgnored private(set) var launchResolver: LaunchContextResolver?
  @ObservationIgnored private var observedActive = false
  @ObservationIgnored private var sensors: AppSensors?
  @ObservationIgnored private let makeSensors: @MainActor () throws -> AppSensors
  @ObservationIgnored private let makeContainer: @MainActor () throws -> ModelContainer
  @ObservationIgnored private let readUnfinished:
    @MainActor (ModelContainer) throws -> [SessionRecord]
  @ObservationIgnored private let makeLaunchResolver:
    @MainActor (TimeInterval) -> LaunchContextResolver

  var locationAccess: LocationAccessState {
    guard let monitor = sensors?.authorization else { return .available }
    return .resolve(
      authorization: monitor.authorizationStatus, accuracy: monitor.accuracyAuthorization)
  }

  init(
    configuration: TrackingConfiguration = .default,
    makeContainer: @escaping @MainActor () throws -> ModelContainer = {
      try ModelContainerFactory.make()
    },
    makeSensors: @escaping @MainActor () throws -> AppSensors = {
      try AppSensors.make(arguments: ProcessInfo.processInfo.arguments)
    },
    readUnfinished: @escaping @MainActor (ModelContainer) throws -> [SessionRecord] = {
      try AppDependencies.readUnfinishedSessions(container: $0)
    },
    makeLaunchResolver: @escaping @MainActor (TimeInterval) -> LaunchContextResolver = {
      LaunchContextResolver(timeout: $0)
    }
  ) {
    self.configuration = configuration
    self.makeContainer = makeContainer
    self.makeSensors = makeSensors
    self.readUnfinished = readUnfinished
    self.makeLaunchResolver = makeLaunchResolver
    prepareDependencies()
  }

  func beginRecovery(launch: LaunchContext) {
    beginRecovery { LaunchContextResolver(known: launch) }
  }

  func beginRecovery(locationLaunch: Bool) {
    beginRecovery {
      if locationLaunch {
        return LaunchContextResolver(known: .background, reason: .locationOption)
      }
      // SwiftUI may have delivered its initial active value before the delegate starts recovery.
      if observedActive { return LaunchContextResolver(known: .foreground, reason: .sceneActive) }
      return makeLaunchResolver(configuration.launchContextTimeout)
    }
  }

  private func beginRecovery(makeResolver: () -> LaunchContextResolver) {
    guard recoveryTask == nil, let dependencies else { return }
    let resolver = makeResolver()
    do {
      let readUnfinished = readUnfinished
      recoveryTask = try RecoveryCoordinator(
        engine: dependencies.engine,
        readUnfinishedSessions: { try readUnfinished(dependencies.container) }
      ).beginRecovery(resolvingLaunch: resolver)
      launchResolver = resolver
      // Ready means recovery was handed to the engine, not that authorization has completed.
      state = .ready
    } catch {
      state = .failed(StartupFailure(kind: .recovery, detail: error.localizedDescription))
    }
  }

  func retry() {
    guard case .failed = state, recoveryTask == nil else { return }
    if dependencies == nil { prepareDependencies() }
    // An explicit retry from the UI must not reuse a background launch's auto-resume policy.
    beginRecovery { LaunchContextResolver(known: .foreground, reason: .retry) }
  }

  @discardableResult
  func didEnterBackground() -> Task<Void, Never>? {
    guard let engine = dependencies?.engine else { return nil }
    // This task outlives the view and does not wait for recovery's authorization result.
    return Task { await engine.flush() }
  }

  func didBecomeActive() {
    if !observedActive {
      observedActive = true
      if let resolver = launchResolver {
        let accepted = resolver.resolve(.foreground)
        launchLogger.info(
          "Launch \(resolver.id, privacy: .public): first scene active after \(String(describing: resolver.elapsed), privacy: .public), accepted \(accepted)"
        )
      }
    }
    sensors?.authorization?.refreshAuthorization()
  }

  private func prepareDependencies() {
    do {
      if sensors == nil { sensors = try makeSensors() }
    } catch let failure as StartupFailure {
      state = .failed(failure)
      return
    } catch {
      // Replay failures arrive as StartupFailure with a specific kind; anything else is generic.
      state = .failed(StartupFailure(kind: .sensors, detail: error.localizedDescription))
      return
    }
    guard let sensors else { return }
    do {
      dependencies = AppDependencies(
        container: try makeContainer(), sensors: sensors, configuration: configuration)
      state = .waitingForLaunch
    } catch {
      state = .failed(StartupFailure(kind: .storage, detail: error.localizedDescription))
    }
  }
}

let launchLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "Promenade", category: "launch")
