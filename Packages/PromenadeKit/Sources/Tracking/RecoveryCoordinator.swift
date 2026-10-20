import Domain
import Foundation

/// The app supplies synchronous SessionReader access and determines LaunchContext using UIKit.
/// Tracking itself does not depend on either SwiftData or UIApplication.
@MainActor
public struct RecoveryCoordinator {
  private let engine: TrackingEngine
  private let readUnfinishedSessions: @MainActor () throws -> [SessionRecord]
  private let dates: any DateProvider

  public init(
    engine: TrackingEngine, dates: any DateProvider = SystemDateProvider(),
    readUnfinishedSessions: @escaping @MainActor () throws -> [SessionRecord]
  ) {
    self.engine = engine
    self.dates = dates
    self.readUnfinishedSessions = readUnfinishedSessions
  }

  /// Call directly from didFinishLaunching, without wrapping the call in a Task.
  /// Resources and the recovery task are created synchronously; await the result only afterward.
  @discardableResult
  public func beginRecovery(launch: LaunchContext) throws -> Task<Void, Never> {
    let sessions = try readUnfinishedSessions()
    return engine.beginRecovery(sessions: sessions, launch: launch, now: dates.now())
  }
}
