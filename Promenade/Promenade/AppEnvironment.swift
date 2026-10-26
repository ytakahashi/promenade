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
  @ObservationIgnored private(set) var refreshTask: Task<Void, Never>?
  @ObservationIgnored private(set) var recoveryCompletionTask: Task<Void, Never>?
  @ObservationIgnored private var recoveryCompleted = false
  @ObservationIgnored private var isActive = false
  @ObservationIgnored private var observedActive = false
  @ObservationIgnored private var sensors: AppSensors?
  @ObservationIgnored private let makeSensors: @MainActor () throws -> AppSensors
  @ObservationIgnored private let makeContainer: @MainActor () throws -> ModelContainer
  @ObservationIgnored private let readUnfinished:
    @MainActor (ModelContainer) throws -> [SessionRecord]
  @ObservationIgnored private let makeLaunchResolver:
    @MainActor (TimeInterval) -> LaunchContextResolver

  @ObservationIgnored private let readRecomputeIDs: @MainActor (ModelContainer) throws -> [UUID]

  var locationAccess: LocationAccessState {
    guard let monitor = sensors?.authorization else { return .available }
    return .resolve(
      authorization: monitor.authorizationStatus, accuracy: monitor.accuracyAuthorization,
      servicesEnabled: monitor.locationServicesEnabled)
  }

  init(
    configuration: TrackingConfiguration = .default,
    makeContainer: @escaping @MainActor () throws -> ModelContainer = {
      try AppEnvironment.makeContainer(arguments: ProcessInfo.processInfo.arguments)
    },
    makeSensors: @escaping @MainActor () throws -> AppSensors = {
      try AppSensors.make(arguments: ProcessInfo.processInfo.arguments)
    },
    readUnfinished: @escaping @MainActor (ModelContainer) throws -> [SessionRecord] = {
      try AppDependencies.readUnfinishedSessions(container: $0)
    },
    readRecomputeIDs: @escaping @MainActor (ModelContainer) throws -> [UUID] = {
      try AppDependencies.readRecomputeIDs(container: $0)
    },
    makeLaunchResolver: @escaping @MainActor (TimeInterval) -> LaunchContextResolver = {
      LaunchContextResolver(timeout: $0)
    }
  ) {
    self.configuration = configuration
    self.makeContainer = makeContainer
    self.makeSensors = makeSensors
    self.readUnfinished = readUnfinished
    self.readRecomputeIDs = readRecomputeIDs
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
      if let recoveryTask {
        recoveryCompletionTask = Task { [weak self] in
          await recoveryTask.value
          guard !Task.isCancelled, !recoveryTask.isCancelled, let self else { return }
          self.recoveryCompleted = true
          self.startRefreshIfReady()
        }
      }
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
    // Only background ends the attempt. Inactive is frequent (system alerts, Control Center)
    // while the app stays in the foreground, and would otherwise skip recomputation until the
    // next launch.
    isActive = false
    refreshTask?.cancel()
    guard let engine = dependencies?.engine else { return nil }
    // This task outlives the view and does not wait for recovery's authorization result.
    return Task { await engine.flush() }
  }

  func didBecomeActive() {
    isActive = true
    startRefreshIfReady()
    if !observedActive {
      observedActive = true
      if let resolver = launchResolver {
        let accepted = resolver.resolve(.foreground)
        launchLogger.info(
          "Launch \(resolver.id, privacy: .public): first scene active after \(String(describing: resolver.elapsed), privacy: .public), accepted \(accepted)"
        )
      }
    }
    if let monitor = sensors?.authorization {
      monitor.refreshAuthorization()
      // Settings may have turned Location Services on or off while the app was inactive.
      Task { await monitor.refreshServicesEnabled() }
    }
  }

  private func startRefreshIfReady() {
    guard recoveryCompleted, isActive, refreshTask == nil, let dependencies else { return }
    // Keep the task even after completion: interruptions are retried only on the next launch.
    refreshTask = Task { await dependencies.refresher.run() }
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
        container: try makeContainer(), sensors: sensors, configuration: configuration,
        readRecomputeIDs: readRecomputeIDs)
      state = .waitingForLaunch
    } catch let failure as StartupFailure {
      state = .failed(failure)
    } catch {
      state = .failed(StartupFailure(kind: .storage, detail: error.localizedDescription))
    }
  }

  isolated deinit {
    refreshTask?.cancel()
    recoveryCompletionTask?.cancel()
  }

  /// Debug builds can store walks at `-StoreURL` so UI tests never touch the regular store. An
  /// invalid option is reported rather than silently falling back to the regular store.
  static func makeContainer(arguments: [String]) throws -> ModelContainer {
    #if DEBUG
      let url: URL?
      let seedCount: Int?
      do {
        url = try StoreLaunchOptions.parse(arguments)
        seedCount = try SeedLaunchOptions.parse(arguments)
      } catch {
        throw StartupFailure(kind: .storeArguments, detail: error.localizedDescription)
      }
      // Seeding must never write generated walks into the user's regular store.
      if seedCount != nil, url == nil {
        throw StartupFailure(kind: .storeArguments, detail: "-SeedSessions requires -StoreURL.")
      }
      if let url {
        let container = try ModelContainerFactory.make(url: url)
        if let seedCount {
          try DebugSessionSeeder.seed(
            count: seedCount, container: container, now: Date(), calendar: .current)
        }
        return container
      }
    #endif
    return try ModelContainerFactory.make()
  }
}

let launchLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "Promenade", category: "launch")
