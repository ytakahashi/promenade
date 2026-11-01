import XCTest

final class PromenadeUITestsLaunchTests: XCTestCase {

  override class var runsForEachTargetApplicationUIConfiguration: Bool {
    true
  }

  private var store: UITestStore!

  override func setUpWithError() throws {
    continueAfterFailure = false
    store = try UITestStore()
  }

  override func tearDownWithError() throws {
    store.remove()
  }

  @MainActor
  func testLaunch() throws {
    let app = XCUIApplication()
    app.launchArguments = store.launchArguments
    app.launch()

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Launch Screen"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
