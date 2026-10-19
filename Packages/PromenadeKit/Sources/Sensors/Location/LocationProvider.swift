public protocol LocationProvider: Sendable {
  /// Each call creates a new subscription. Cancel the consuming task to stop updates.
  func events() -> AsyncThrowingStream<LocationEvent, any Error>
}
