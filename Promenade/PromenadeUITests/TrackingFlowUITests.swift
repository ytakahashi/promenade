import XCTest

/// Recording flows driven by Replay against a store of their own, so the regular store is never
/// read or reset.
final class TrackingFlowUITests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    continueAfterFailure = false
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Self.writeReplay(to: directory.appendingPathComponent("walk.gpx"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  @MainActor
  func testRecordingContinuesWhileOtherTabsAreShown() {
    let app = launch()
    start(app)
    let before = walkingTime(app)
    app.tabBars.buttons["History"].tap()
    app.tabBars.buttons["Statistics"].tap()
    sleep(3)
    XCTAssertEqual(app.tabBars.buttons["Tracking"].value as? String, "Recording")
    app.tabBars.buttons["Tracking"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    XCTAssertNotEqual(walkingTime(app), before)
  }

  @MainActor
  func testCancelledConfirmationsKeepRecording() {
    let app = launch()
    start(app)
    app.buttons["Pause"].tap()
    XCTAssertTrue(app.alerts["Pause Walk?"].waitForExistence(timeout: 5))
    app.alerts.buttons["Cancel"].tap()
    app.buttons["Finish"].press(forDuration: 1.6)
    XCTAssertTrue(app.alerts["Finish Walk?"].waitForExistence(timeout: 5))
    app.alerts.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.alerts.firstMatch.exists)
    XCTAssertEqual(app.tabBars.buttons["Tracking"].value as? String, "Recording")
  }

  @MainActor
  func testFinishShowsTheSummaryOnce() {
    let app = launch()
    start(app)
    app.buttons["Finish"].press(forDuration: 1.6)
    XCTAssertTrue(app.alerts["Finish Walk?"].waitForExistence(timeout: 5))
    app.alerts.buttons["Finish"].tap()
    assertSummary(app)
    app.navigationBars.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
    app.tabBars.buttons["History"].tap()
    app.tabBars.buttons["Tracking"].tap()
    XCTAssertFalse(app.navigationBars["Walk Summary"].waitForExistence(timeout: 2))
  }

  @MainActor
  func testFinishingAfterTerminationAsksAndShowsTheSummary() {
    let app = launch()
    start(app)
    app.terminate()
    app.launch()
    let recovery = app.alerts["Continue Previous Walk?"]
    XCTAssertTrue(recovery.waitForExistence(timeout: 10))
    recovery.buttons["Finish"].tap()
    assertSummary(app)
  }

  // MARK: Helpers

  @MainActor
  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ReplayGPX", directory.appendingPathComponent("walk.gpx").path,
      "-StoreURL", directory.appendingPathComponent("walks.store").path,
    ]
    app.launch()
    return app
  }

  @MainActor
  private func start(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
    app.buttons["Start"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
    // Let a few replayed points arrive so the walk has a route.
    sleep(3)
  }

  @MainActor
  private func walkingTime(_ app: XCUIApplication) -> String? {
    // The metric is one accessibility element whose value is the spoken duration.
    app.otherElements["Walking time"].firstMatch.value as? String
  }

  @MainActor
  private func assertSummary(_ app: XCUIApplication) {
    XCTAssertTrue(app.navigationBars["Walk Summary"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Distance"].firstMatch.exists)
  }

  /// A straight walk at about 1.4 m/s with one point per second.
  private static func writeReplay(to url: URL) throws {
    let start = Date(timeIntervalSince1970: 1_767_225_600)
    let formatter = ISO8601DateFormatter()
    let points = (0..<900).map { index in
      let latitude = 35.68 + Double(index) * 1.4 / 111_000
      let time = formatter.string(from: start.addingTimeInterval(Double(index)))
      return "<trkpt lat=\"\(latitude)\" lon=\"139.75\"><time>\(time)</time></trkpt>"
    }
    let gpx =
      "<?xml version=\"1.0\"?><gpx version=\"1.1\" creator=\"Promenade UI tests\"><trk><trkseg>"
      + points.joined() + "</trkseg></trk></gpx>"
    try Data(gpx.utf8).write(to: url)
  }
}
