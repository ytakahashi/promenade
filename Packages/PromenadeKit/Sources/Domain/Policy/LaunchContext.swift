/// How the app was launched, independent of platform lifecycle types.
public enum LaunchContext: Sendable {
  case background
  case foreground
}
