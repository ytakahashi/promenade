#if DEBUG
  import Domain
  import Foundation
  import Synchronization
  import Testing

  @testable import Sensors

  struct ReplayLocationProviderTests {
    @Test func shiftsAndScalesTimestampsWithoutCollapsingGaps() async throws {
      let clock = TestReplayClock()
      let provider = try ReplayLocationProvider(
        points: [point(10, north: 0), point(20, north: 1), point(150, north: 2)],
        speedMultiplier: 2, makeClock: { clock })
      let received = try await locations(from: provider)
      #expect(
        received.map(\.timestamp) == [0.0, 5, 70].map { clock.startDate.addingTimeInterval($0) })
      #expect(received.map(\.coordinate.latitude) == [35, 36, 37])
      #expect(await clock.deadlines == [0, 5, 70])
    }

    @Test func resubscriptionContinuesOnSharedTimeline() async throws {
      let clock = TestReplayClock()
      let creations = Mutex(0)
      let provider = try ReplayLocationProvider(
        points: [point(0, north: 0), point(10, north: 1), point(20, north: 2)],
        speedMultiplier: 1,
        makeClock: {
          creations.withLock { $0 += 1 }
          return clock
        })
      // The first subscription stops early, as when the user pauses.
      for try await _ in provider.events() { break }
      // Points due while unsubscribed are skipped, like positions not recorded during a pause.
      await clock.setElapsed(15)
      let resumed = try await locations(from: provider)
      #expect(resumed.map(\.coordinate.latitude) == [37])
      #expect(resumed.map(\.timestamp) == [clock.startDate.addingTimeInterval(20)])
      #expect(creations.withLock { $0 } == 1)
      // A copy of the provider shares the same timeline.
      let copy = provider
      await clock.setElapsed(25)
      #expect(try await locations(from: copy).isEmpty)
    }

    private func locations(from provider: ReplayLocationProvider) async throws -> [TrackPoint] {
      var received: [TrackPoint] = []
      for try await event in provider.events() {
        guard case .location(let point, let stationary) = event else {
          Issue.record("Unexpected event")
          continue
        }
        #expect(!stationary)
        received.append(point)
      }
      return received
    }

    @Test(arguments: [0.0, -1, .infinity, .nan])
    func rejectsInvalidSpeed(_ speed: Double) {
      #expect(throws: GPXError.invalidSpeedMultiplier) {
        try ReplayLocationProvider(points: [point(0)], speedMultiplier: speed)
      }
    }

    @Test func rejectsInvalidTimeline() {
      #expect(throws: GPXError.noTrackPoints) { try ReplayLocationProvider(points: []) }
      for points in [[point(1), point(1)], [point(2), point(1)], [point(0), point(1e15)]] {
        #expect(throws: GPXError.invalidReplayTimeline) {
          try ReplayLocationProvider(points: points)
        }
      }
    }

    @Test func cancellationInterruptsPendingSleep() async throws {
      let clock = BlockingReplayClock()
      let provider = try ReplayLocationProvider(
        points: [point(0), point(100)], speedMultiplier: 1, makeClock: { clock })
      let consumer = Task {
        for try await _ in provider.events() {}
      }
      await clock.waitUntilSleeping()
      consumer.cancel()
      _ = await consumer.result
      await clock.waitUntilCancelled()
    }

    private func point(_ seconds: Double, north: Double = 0) -> TrackPoint {
      TrackPoint(
        timestamp: Date(timeIntervalSinceReferenceDate: seconds),
        coordinate: Coordinate(latitude: 35 + north, longitude: 139), horizontalAccuracy: 5,
        altitude: 42, verticalAccuracy: 5, speed: -1, speedAccuracy: -1, course: -1)
    }
  }

  private actor TestReplayClock: ReplayClock {
    nonisolated let startDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var deadlines: [TimeInterval] = []
    private var currentElapsed: TimeInterval = 0
    func setElapsed(_ value: TimeInterval) { currentElapsed = value }
    func elapsed() -> TimeInterval { currentElapsed }
    func sleep(until offset: TimeInterval) { deadlines.append(offset) }
  }

  private actor BlockingReplayClock: ReplayClock {
    nonisolated let startDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func elapsed() -> TimeInterval { 0 }
    private var sleeping = false
    private var cancelled = false
    private var sleepingWaiter: CheckedContinuation<Void, Never>?
    private var cancelledWaiter: CheckedContinuation<Void, Never>?

    func sleep(until offset: TimeInterval) async throws {
      guard offset > 0 else { return }
      sleeping = true
      sleepingWaiter?.resume()
      sleepingWaiter = nil
      do {
        try await Task.sleep(for: .seconds(3600))
      } catch {
        cancelled = true
        cancelledWaiter?.resume()
        cancelledWaiter = nil
        throw error
      }
    }

    func waitUntilSleeping() async {
      if !sleeping { await withCheckedContinuation { sleepingWaiter = $0 } }
    }

    func waitUntilCancelled() async {
      if !cancelled { await withCheckedContinuation { cancelledWaiter = $0 } }
    }
  }
#endif
