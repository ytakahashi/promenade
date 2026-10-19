/// The lifecycle state of a walking session.
///
/// Raw values are persisted as strings; do not change them without a schema migration.
public enum SessionState: String, Sendable {
  case recording
  case paused
  case finished
}
