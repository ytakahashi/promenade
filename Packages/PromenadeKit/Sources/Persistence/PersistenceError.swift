import Foundation

public enum PersistenceError: Error, Sendable, Equatable {
  case sessionNotFound(UUID)
  case duplicateSession(UUID)
  case invalidState
  case sessionNotFinished
  case noOpenSegment
  case segmentAlreadyOpen
  case invalidDate
  case invalidPointTimestamp
  case invalidSplitReason
  case invalidStructure
  case invalidStoredValue(field: String, value: String)
}
