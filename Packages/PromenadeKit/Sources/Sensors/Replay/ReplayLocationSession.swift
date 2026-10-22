#if DEBUG
  @MainActor
  public final class ReplayLocationSession: LocationSession {
    public init() {}
    public var canActivateWithoutPrompt: Bool { true }
    public func beginActivation() {}
    public func activate() async throws -> LocationAccessResult {
      try Task.checkCancellation()
      return .granted
    }
    public func deactivate() {}
  }
#endif
