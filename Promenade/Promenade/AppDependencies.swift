import Domain
import Features
import Foundation
import Persistence
import Sensors
import SwiftData
import Tracking

struct AppDependencies {
  let container: ModelContainer
  let store: SwiftDataTrackingStore
  let engine: TrackingEngine
  let pedometer: any PedometerProvider

  init(container: ModelContainer, sensors: AppSensors, configuration: TrackingConfiguration) {
    self.container = container
    store = SwiftDataTrackingStore(container: container, configuration: configuration)
    pedometer = sensors.pedometer
    engine = TrackingEngine(
      store: store, provider: sensors.provider, locationSession: sensors.session,
      pedometer: sensors.pedometer, configuration: configuration)
  }

  func readSession(id: UUID) throws -> SessionRecord? {
    try Self.reader(container: container).session(id: id)
  }

  func motionAccess() -> MotionAccessState {
    MotionAccessState(pedometer.access)
  }

  func listSessions() throws -> [SessionListItem] {
    try Self.reader(container: container).finishedSessions()
  }

  static func readUnfinishedSessions(container: ModelContainer) throws -> [SessionRecord] {
    try reader(container: container).unfinishedSessions()
  }

  private static func reader(container: ModelContainer) -> SessionReader {
    // A fresh context sees saves from the recording actor instead of cached launch models.
    let context = ModelContext(container)
    context.autosaveEnabled = false
    return SessionReader(context: context)
  }
}
