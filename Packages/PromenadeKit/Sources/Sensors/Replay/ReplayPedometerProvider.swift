#if DEBUG
  import Foundation

  /// Counts steps at a constant cadence so step display can be checked where Core Motion is
  /// unavailable, such as the simulator.
  public struct ReplayPedometerProvider: PedometerProvider {
    private let measuresSteps: Bool
    private let stepsPerMinute: Double
    private let now: @Sendable () -> Date
    private let tick: @Sendable () async throws -> Void

    /// - Parameter measuresSteps: When false, behaves like a device with motion access denied.
    public init(measuresSteps: Bool = true, stepsPerMinute: Double = 110) {
      self.init(
        measuresSteps: measuresSteps, stepsPerMinute: stepsPerMinute, now: { Date() },
        tick: { try await Task.sleep(for: .seconds(1)) })
    }

    init(
      measuresSteps: Bool, stepsPerMinute: Double, now: @escaping @Sendable () -> Date,
      tick: @escaping @Sendable () async throws -> Void
    ) {
      self.measuresSteps = measuresSteps
      self.stepsPerMinute = stepsPerMinute
      self.now = now
      self.tick = tick
    }

    public var access: MotionAccess { measuresSteps ? .allowed : .denied }

    public func steps(from start: Date, to end: Date) async -> Int? {
      measuresSteps ? count(from: start, to: end) : nil
    }

    /// Yields the steps up to the current time once per tick until cancelled.
    public func liveSteps(from start: Date) -> AsyncStream<Int> {
      AsyncStream { continuation in
        guard measuresSteps else {
          continuation.finish()
          return
        }
        let task = Task {
          do {
            while true {
              try Task.checkCancellation()
              continuation.yield(count(from: start, to: now()))
              try await tick()
            }
          } catch {}
          continuation.finish()
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
      }
    }

    private func count(from start: Date, to end: Date) -> Int {
      Int((max(0, end.timeIntervalSince(start)) / 60 * stepsPerMinute).rounded(.down))
    }
  }
#endif
