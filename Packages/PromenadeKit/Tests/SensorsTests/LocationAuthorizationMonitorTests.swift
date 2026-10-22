import Foundation
import Synchronization
import Testing

@testable import Sensors

@MainActor
struct LocationAuthorizationMonitorTests {
  @Test func servicesStateIsReadOffTheMainThread() async {
    let readOnMain = Mutex<Bool?>(nil)
    let enabled = Mutex(false)
    let monitor = LocationAuthorizationMonitor(readServicesEnabled: {
      readOnMain.withLock { $0 = Thread.isMainThread }
      return enabled.withLock { $0 }
    })
    await monitor.refreshServicesEnabled()
    #expect(readOnMain.withLock { $0 } == false)
    #expect(!monitor.locationServicesEnabled)

    enabled.withLock { $0 = true }
    await monitor.refreshServicesEnabled()
    #expect(monitor.locationServicesEnabled)
  }
}
