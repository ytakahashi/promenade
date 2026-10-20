import XCTest

final class PromenadeUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testTabsRemainAvailableAfterLaunch() {
    let app = XCUIApplication()
    app.launch()
    assertTabs(app)
    app.tabBars.buttons["History"].tap()
    app.tabBars.buttons["Statistics"].tap()
    app.tabBars.buttons["Tracking"].tap()
    XCTAssertTrue(app.tabBars.buttons["Tracking"].isSelected)
  }

  @MainActor
  func testInvalidReplayOptionsDoNotOpenTracking() {
    let app = XCUIApplication()
    app.launchArguments = ["-ReplaySpeed", "2"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Invalid Replay Options"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Retry"].exists)
    XCTAssertFalse(app.tabBars.firstMatch.exists)
  }

  @MainActor
  func testReplayFileCanBeRepairedAndRetried() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".gpx")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("invalid XML".utf8).write(to: url)
    let app = XCUIApplication()
    app.launchArguments = ["-ReplayGPX", url.path]
    app.launch()
    XCTAssertTrue(app.staticTexts["Invalid Replay Data"].waitForExistence(timeout: 10))
    try Data(
      """
      <gpx><trk><trkseg><trkpt lat="35" lon="139">
      <time>2026-10-20T00:00:00Z</time></trkpt></trkseg></trk></gpx>
      """.utf8
    ).write(to: url)
    app.buttons["Retry"].tap()
    assertTabs(app)
  }

  @MainActor
  private func assertTabs(_ app: XCUIApplication) {
    XCTAssertTrue(app.tabBars.buttons["Tracking"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.tabBars.buttons["History"].exists)
    XCTAssertTrue(app.tabBars.buttons["Statistics"].exists)
  }
}
