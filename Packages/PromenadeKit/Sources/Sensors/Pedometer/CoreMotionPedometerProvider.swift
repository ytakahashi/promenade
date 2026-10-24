import CoreMotion
import Foundation
import os

public struct CoreMotionPedometerProvider: PedometerProvider {
  private let readAccess: @Sendable () -> MotionAccess
  private let query: @Sendable (Date, Date) async throws -> Int
  private let updates: @Sendable (Date) -> AsyncThrowingStream<Int, any Error>

  /// The first query or live subscription shows the motion permission prompt; Core Motion has no
  /// separate request API.
  public init() {
    self.init(
      access: {
        guard CMPedometer.isStepCountingAvailable() else { return .unavailable }
        return MotionAccess(CMPedometer.authorizationStatus())
      },
      query: { start, end in
        guard CMPedometer.isStepCountingAvailable() else { throw PedometerError.unavailable }
        let pedometer = CMPedometer()
        return try await withCheckedThrowingContinuation { continuation in
          pedometer.queryPedometerData(from: start, to: end) { data, error in
            // Capturing the pedometer keeps it alive until the handler runs.
            withExtendedLifetime(pedometer) {
              if let data {
                continuation.resume(returning: data.numberOfSteps.intValue)
              } else {
                continuation.resume(throwing: error ?? PedometerError.noData)
              }
            }
          }
        }
      },
      updates: { start in
        AsyncThrowingStream { continuation in
          guard CMPedometer.isStepCountingAvailable() else {
            continuation.finish(throwing: PedometerError.unavailable)
            return
          }
          // One pedometer per subscription: stopUpdates() on a shared instance would also stop
          // other subscriptions. CMPedometer is not Sendable, but it is only started here and
          // stopped once on termination.
          nonisolated(unsafe) let pedometer = CMPedometer()
          pedometer.startUpdates(from: start) { data, error in
            if let data {
              continuation.yield(data.numberOfSteps.intValue)
            } else {
              continuation.finish(throwing: error ?? PedometerError.noData)
            }
          }
          continuation.onTermination = { @Sendable _ in pedometer.stopUpdates() }
        }
      })
  }

  /// Inject the Core Motion calls so error handling and cancellation use the production bridge
  /// in tests.
  init(
    access: @escaping @Sendable () -> MotionAccess,
    query: @escaping @Sendable (Date, Date) async throws -> Int,
    updates: @escaping @Sendable (Date) -> AsyncThrowingStream<Int, any Error>
  ) {
    readAccess = access
    self.query = query
    self.updates = updates
  }

  public var access: MotionAccess { readAccess() }

  public func steps(from start: Date, to end: Date) async -> Int? {
    do {
      return try await query(start, end)
    } catch {
      // Expected when motion access is denied or the interval is older than the OS keeps.
      pedometerLogger.info(
        "Step query failed: \(String(describing: error), privacy: .private)")
      return nil
    }
  }

  public func liveSteps(from start: Date) -> AsyncStream<Int> {
    let updates = updates
    return AsyncStream { continuation in
      let task = Task {
        do {
          for try await steps in updates(start) {
            try Task.checkCancellation()
            continuation.yield(steps)
          }
        } catch {
          if !(error is CancellationError) {
            pedometerLogger.info(
              "Live steps ended: \(String(describing: error), privacy: .private)")
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }
}

enum PedometerError: Error {
  case unavailable
  /// Core Motion reported neither data nor an error.
  case noData
}

extension MotionAccess {
  init(_ status: CMAuthorizationStatus) {
    switch status {
    case .notDetermined: self = .notDetermined
    case .authorized: self = .allowed
    case .denied: self = .denied
    case .restricted: self = .restricted
    @unknown default: self = .denied
    }
  }
}

private let pedometerLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "Promenade", category: "sensors")
