import Domain

public enum LocationEvent: Sendable, Equatable {
  case location(TrackPoint, stationary: Bool)
  case stationary
  case unavailable
  case accessLost(LocationAccessIssue)
}

public enum LocationAccessIssue: Sendable, Equatable {
  case denied
  case servicesDisabled
  case accuracyLimited
}

public enum LocationAccessResult: Sendable, Equatable {
  case granted
  case denied(LocationAccessIssue)
}

public enum LocationSensorError: Error, Sendable, Equatable {
  case diagnosticsEnded
}
