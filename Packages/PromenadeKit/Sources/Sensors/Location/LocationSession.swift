@MainActor
public protocol LocationSession: AnyObject {
  /// Whether access is already granted, so creating resources cannot show a permission prompt.
  ///
  /// Launch recovery reserves resources before it knows whether the launch is in the foreground.
  /// It must not prompt for access before the user has chosen to resume.
  var canActivateWithoutPrompt: Bool { get }
  /// Creates resources synchronously, including during application launch recovery.
  func beginActivation()
  /// Reuses an activation already begun. Cancellation ends that activation, including other waiters.
  func activate() async throws -> LocationAccessResult
  func deactivate()
}
