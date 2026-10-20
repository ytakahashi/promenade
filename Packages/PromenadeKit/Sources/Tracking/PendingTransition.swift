import Foundation
import Sensors

public struct PendingTransition: Sendable, Equatable {
  public enum Kind: Sendable { case pause, finish }
  public let id: UUID
  public let kind: Kind
  public let date: Date
  var events: [LocationEvent] = []

  init(kind: Kind, date: Date) {
    id = UUID()
    self.kind = kind
    self.date = date
  }
}
