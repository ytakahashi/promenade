import Testing

@testable import Sensors

struct CoreLocationProviderTests {
  private enum Failure: Error { case injected }

  @Test func deliversEventsInOrderAndFinishes() async throws {
    let provider = CoreLocationProvider(
      updates: {
        AsyncStream<Int> { continuation in
          for value in [0, 1, 2] { continuation.yield(value) }
          continuation.finish()
        }
      },
      transform: { value in
        switch value {
        case 1: .stationary
        case 2: .unavailable
        default: nil
        }
      })
    var events: [LocationEvent] = []
    for try await event in provider.events() { events.append(event) }
    #expect(events == [.stationary, .unavailable])
  }

  @Test func propagatesUpstreamFailure() async {
    let provider = CoreLocationProvider(
      updates: {
        AsyncThrowingStream<LocationEvent, any Error> { continuation in
          continuation.finish(throwing: Failure.injected)
        }
      }, transform: { $0 })
    await #expect(throws: Failure.injected) {
      for try await _ in provider.events() {}
    }
  }

  @Test func consumerCancellationStopsUpstream() async throws {
    let (source, sourceContinuation) = AsyncStream<LocationEvent>.makeStream()
    let (terminated, terminationContinuation) = AsyncStream<Void>.makeStream()
    sourceContinuation.onTermination = { _ in terminationContinuation.yield(()) }
    let provider = CoreLocationProvider(updates: { source }, transform: { $0 })
    let (received, receivedContinuation) = AsyncStream<Void>.makeStream()
    let consumer = Task {
      for try await _ in provider.events() { receivedContinuation.yield(()) }
    }
    sourceContinuation.yield(.stationary)
    for await _ in received { break }
    consumer.cancel()
    _ = await consumer.result
    for await _ in terminated { break }
  }
}
