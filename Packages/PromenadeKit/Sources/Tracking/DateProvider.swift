import Foundation

@MainActor
public protocol DateProvider {
  func now() -> Date
}

public struct SystemDateProvider: DateProvider {
  public init() {}
  public func now() -> Date { Date() }
}
