import Domain
import Foundation
import Testing

@testable import Tracking

@MainActor
struct LaunchContextResolverTests {
  @Test func knownContextDoesNotWait() async throws {
    let resolver = LaunchContextResolver(known: .background, reason: .locationOption)
    #expect(try await resolver.wait() == .background)
    #expect(!resolver.resolve(.foreground))
    #expect(resolver.reason == .locationOption)
  }

  @Test func activeBeforeWaitingDoesNotStartTimer() async throws {
    let clock = LaunchTestClock()
    let resolver = LaunchContextResolver(
      timeout: 3, sleepUntil: { try await clock.sleep(until: $0) })
    #expect(resolver.resolve(.foreground))
    #expect(try await resolver.wait() == .foreground)
    #expect(clock.deadline == nil)
  }

  @Test(arguments: [false, true])
  func firstResolutionWinsAndStopsTimer(deadlineFirst: Bool) async throws {
    let clock = LaunchTestClock()
    // A delayed recovery task still uses the deadline anchored at construction.
    let origin = ContinuousClock.now.advanced(by: .seconds(-10))
    let resolver = LaunchContextResolver(
      timeout: 3, now: origin, sleepUntil: { try await clock.sleep(until: $0) })
    let task = Task { try await resolver.wait() }
    await clock.waitUntilSleeping()
    #expect(clock.deadline == origin.advanced(by: .seconds(3)))
    if deadlineFirst {
      clock.advance()
      #expect(try await task.value == .background)
      #expect(!resolver.resolve(.foreground))
      #expect(resolver.reason == .deadline)
    } else {
      #expect(resolver.resolve(.foreground))
      #expect(try await task.value == .foreground)
      await eventually { clock.cancelled }
      clock.advance()
      #expect(resolver.context == .foreground)
      #expect(resolver.reason == .sceneActive)
    }
    #expect(!resolver.resolve(.background))
  }

  @Test(arguments: [false, true])
  func cancellationBeforeOrDuringWaitCompletes(cancelBeforeRunning: Bool) async {
    let clock = LaunchTestClock()
    let resolver = LaunchContextResolver(
      timeout: 3, sleepUntil: { try await clock.sleep(until: $0) })
    let task = Task { try await resolver.wait() }
    if !cancelBeforeRunning { await clock.waitUntilSleeping() }
    task.cancel()
    do {
      _ = try await task.value
      Issue.record("Cancelled launch wait returned a context")
    } catch {
      #expect(error is CancellationError)
    }
    #expect(resolver.context == nil)
    #expect(!resolver.resolve(.background))
    if !cancelBeforeRunning {
      await eventually { clock.cancelled }
    } else {
      #expect(clock.deadline == nil)
    }
  }
}
