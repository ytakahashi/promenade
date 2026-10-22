import Domain
import Foundation

/// Resolves one launch without depending on UIKit. Each recovery attempt owns its own resolver.
@MainActor
public final class LaunchContextResolver {
  public enum Reason: String, Sendable {
    case explicit, locationOption, sceneActive, deadline, retry
  }

  public let id = UUID()
  public private(set) var context: LaunchContext?
  public private(set) var reason: Reason?
  private let origin: ContinuousClock.Instant
  private let deadline: ContinuousClock.Instant?
  private let sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void
  private var continuation: CheckedContinuation<LaunchContext, any Error>?
  private var timer: Task<Void, Never>?
  private var cancelled = false

  public init(known context: LaunchContext, reason: Reason = .explicit) {
    origin = .now
    deadline = nil
    sleepUntil = { _ in }
    resolve(context, reason: reason)
  }

  public init(
    timeout: TimeInterval, now: ContinuousClock.Instant = .now,
    sleepUntil: @escaping @Sendable (ContinuousClock.Instant) async throws -> Void = {
      try await Task.sleep(until: $0, clock: .continuous)
    }
  ) {
    precondition(timeout.isFinite && timeout >= 0, "Launch timeout must be finite and nonnegative")
    origin = now
    // Anchor the deadline before scheduling recovery, not when its task eventually starts.
    deadline = now.advanced(by: .seconds(timeout))
    self.sleepUntil = sleepUntil
  }

  public var elapsed: Duration { origin.duration(to: .now) }

  @discardableResult
  public func resolve(_ context: LaunchContext, reason: Reason = .sceneActive) -> Bool {
    guard self.context == nil, !cancelled else { return false }
    self.context = context
    self.reason = reason
    timer?.cancel()
    timer = nil
    let continuation = continuation
    self.continuation = nil
    trackingLogger.info(
      "Launch \(self.id, privacy: .public): resolved \(String(describing: context), privacy: .public) by \(reason.rawValue, privacy: .public) after \(String(describing: self.elapsed), privacy: .public)"
    )
    continuation?.resume(returning: context)
    return true
  }

  /// Only the recovery operation waits. Scene callbacks resolve without joining its queue.
  func wait() async throws -> LaunchContext {
    if Task.isCancelled {
      cancel()
      throw CancellationError()
    }
    if let context { return context }
    if cancelled { throw CancellationError() }
    let result = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        precondition(self.continuation == nil, "A launch has only one recovery waiter")
        self.continuation = continuation
        if let deadline {
          let sleepUntil = sleepUntil
          timer = Task { [weak self] in
            do {
              try await sleepUntil(deadline)
              try Task.checkCancellation()
              self?.resolve(.background, reason: .deadline)
            } catch {
              if !Task.isCancelled { self?.cancel() }
            }
          }
        }
      }
    } onCancel: {
      // Enqueue on MainActor so even cancellation before continuation registration is handled.
      Task { @MainActor in self.cancel() }
    }
    try Task.checkCancellation()
    return result
  }

  func cancel() {
    guard context == nil, !cancelled else { return }
    cancelled = true
    timer?.cancel()
    timer = nil
    let continuation = continuation
    self.continuation = nil
    continuation?.resume(throwing: CancellationError())
    trackingLogger.info("Launch \(self.id, privacy: .public): resolution cancelled")
  }

  isolated deinit { timer?.cancel() }
}
