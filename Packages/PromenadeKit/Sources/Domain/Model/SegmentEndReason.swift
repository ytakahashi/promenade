/// Why a segment was closed. Determines how the time until the next segment is classified.
///
/// Raw values are persisted as strings; do not change them without a schema migration.
public enum SegmentEndReason: String, Sendable {
  /// Paused by the user. The gap counts as pause time.
  case paused
  /// Finished by the user. Nothing follows.
  case finished
  /// The app was terminated or location access was lost. The gap counts as interruption time.
  case interrupted
  /// No location was received for a while without being stationary. The gap counts as walking time.
  case signalGap
}
