import Foundation
import Synchronization
import Testing

@testable import Sensors

struct CoreMotionPedometerProviderTests {
  private enum Failure: Error { case injected }

  private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  @Test func returnsQueriedStepsForTheInterval() async {
    let provider = CoreMotionPedometerProvider(
      access: { .allowed },
      query: { start, end in Int(end.timeIntervalSince(start)) },
      updates: { _ in AsyncThrowingStream { $0.finish() } })
    #expect(await provider.steps(from: Self.start, to: Self.start.addingTimeInterval(42)) == 42)
  }

  @Test func reportsFailedQueryAsUnmeasured() async {
    let provider = CoreMotionPedometerProvider(
      access: { .denied },
      query: { _, _ in throw Failure.injected },
      updates: { _ in AsyncThrowingStream { $0.finish() } })
    #expect(await provider.steps(from: Self.start, to: Self.start) == nil)
  }

  @Test func liveStepsStartFromTheGivenDateAndFinishOnUpstreamFailure() async {
    let provider = CoreMotionPedometerProvider(
      access: { .allowed },
      query: { _, _ in 0 },
      updates: { start in
        AsyncThrowingStream { continuation in
          #expect(start == Self.start)
          continuation.yield(3)
          continuation.yield(8)
          continuation.finish(throwing: Failure.injected)
        }
      })
    var received: [Int] = []
    for await steps in provider.liveSteps(from: Self.start) { received.append(steps) }
    #expect(received == [3, 8])
  }

  @Test func consumerCancellationStopsUpstream() async {
    let (source, sourceContinuation) = AsyncThrowingStream<Int, any Error>.makeStream()
    let (terminated, terminationContinuation) = AsyncStream<Void>.makeStream()
    sourceContinuation.onTermination = { _ in terminationContinuation.yield(()) }
    let provider = CoreMotionPedometerProvider(
      access: { .allowed }, query: { _, _ in 0 }, updates: { _ in source })
    let (received, receivedContinuation) = AsyncStream<Void>.makeStream()
    let consumer = Task {
      for await _ in provider.liveSteps(from: Self.start) { receivedContinuation.yield(()) }
    }
    sourceContinuation.yield(1)
    for await _ in received { break }
    consumer.cancel()
    _ = await consumer.result
    for await _ in terminated { break }
  }

  @Test func readsAccessOnEveryCall() {
    let current = Mutex(MotionAccess.notDetermined)
    let provider = CoreMotionPedometerProvider(
      access: { current.withLock { $0 } }, query: { _, _ in 0 },
      updates: { _ in AsyncThrowingStream { $0.finish() } })
    #expect(provider.access == .notDetermined)
    current.withLock { $0 = .allowed }
    #expect(provider.access == .allowed)
  }
}
