#if DEBUG
  import Foundation
  import Synchronization
  import Testing

  @testable import Sensors

  struct ReplayPedometerProviderTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test(arguments: [(0.0, 0), (59, 108), (60, 110), (90, 165), (-10, 0)])
    func countsStepsAtConstantCadence(seconds: TimeInterval, steps: Int) async {
      let provider = ReplayPedometerProvider()
      #expect(
        await provider.steps(from: Self.start, to: Self.start.addingTimeInterval(seconds))
          == steps)
      #expect(provider.access == .allowed)
    }

    @Test func liveStepsCountFromTheGivenDateUpToNow() async {
      let elapsed = Mutex<TimeInterval>(0)
      let provider = ReplayPedometerProvider(
        measuresSteps: true, stepsPerMinute: 60,
        now: { Self.start.addingTimeInterval(elapsed.withLock { $0 }) },
        tick: { elapsed.withLock { $0 += 30 } })
      var received: [Int] = []
      for await steps in provider.liveSteps(from: Self.start) {
        received.append(steps)
        if received.count == 3 { break }
      }
      #expect(received == [0, 30, 60])
    }

    @Test func unmeasuredBehavesLikeDeniedAccess() async {
      let provider = ReplayPedometerProvider(measuresSteps: false)
      #expect(provider.access == .denied)
      #expect(await provider.steps(from: Self.start, to: Self.start.addingTimeInterval(60)) == nil)
      var received: [Int] = []
      for await steps in provider.liveSteps(from: Self.start) { received.append(steps) }
      #expect(received.isEmpty)
    }
  }
#endif
