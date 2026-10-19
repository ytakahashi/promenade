@MainActor
public protocol LocationSession: AnyObject {
  /// Creates resources synchronously, including during application launch recovery.
  func beginActivation()
  /// Reuses an activation already begun. Cancellation ends that activation, including other waiters.
  func activate() async throws -> LocationAccessResult
  func deactivate()
}
