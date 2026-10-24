import XCTest

/// Recording flows driven by Replay against a store of their own.
final class TrackingFlowUITests: XCTestCase {
  private var store: UITestStore!

  override func setUpWithError() throws {
    continueAfterFailure = false
    store = try UITestStore()
    try Self.writeReplay(to: store.directory.appendingPathComponent("walk.gpx"))
  }

  override func tearDownWithError() throws {
    store.remove()
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
    // A walk of a few seconds is short, so it is saved explicitly.
    app.alerts.buttons["Save"].tap()
    assertSummary(app)
    app.navigationBars.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
    app.tabBars.buttons["History"].tap()
    app.tabBars.buttons["Tracking"].tap()
    XCTAssertFalse(app.navigationBars["Walk Summary"].waitForExistence(timeout: 2))
  }

  @MainActor
  func testShortWalkCanBeDiscarded() {
    let app = launch()
    start(app)
    app.buttons["Finish"].press(forDuration: 1.6)
    let alert = app.alerts["Finish Walk?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    XCTAssertTrue(alert.buttons["Save"].exists)
    alert.buttons["Discard"].tap()
    XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.navigationBars["Walk Summary"].waitForExistence(timeout: 2))
    XCTAssertEqual(app.tabBars.buttons["Tracking"].value as? String, "Not recording")
    app.tabBars.buttons["History"].tap()
    XCTAssertTrue(app.staticTexts["No Walks Yet"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testSavedWalkAppearsInHistoryAndOpensItsDetails() {
    let app = launch()
    start(app)
    saveAndCloseSummary(app)
    app.tabBars.buttons["History"].tap()
    let row = app.buttons["history.row"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.tap()
    XCTAssertTrue(app.navigationBars["Walk"].waitForExistence(timeout: 5))
    let steps = app.descendants(matching: .any)["Steps"].firstMatch
    XCTAssertTrue(steps.waitForExistence(timeout: 5))
    XCTAssertNotEqual(steps.value as? String, "Not available")
  }

  @MainActor
  func testDeletingAWalkFromHistoryAsksFirst() {
    let app = launch()
    start(app)
    saveAndCloseSummary(app)
    app.tabBars.buttons["History"].tap()
    let row = app.buttons["history.row"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.swipeLeft()
    app.buttons["Delete"].tap()
    let alert = app.alerts["Delete Walk?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    alert.buttons["Cancel"].tap()
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.swipeLeft()
    app.buttons["Delete"].tap()
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    alert.buttons["Delete"].tap()
    XCTAssertTrue(app.staticTexts["No Walks Yet"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testStepsAreShownWhileRecording() {
    let app = launch()
    start(app)
    let steps = app.otherElements["Steps"].firstMatch
    XCTAssertTrue(steps.waitForExistence(timeout: 5))
    XCTAssertNotEqual(steps.value as? String, "Not available")
  }

  @MainActor
  func testUnmeasuredStepsAreShownAsNotAvailable() {
    let app = launch(extraArguments: ["-ReplaySteps", "none"])
    start(app)
    let steps = app.otherElements["Steps"].firstMatch
    XCTAssertTrue(steps.waitForExistence(timeout: 5))
    XCTAssertEqual(steps.value as? String, "Not available")
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
  private func launch(extraArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      ["-ReplayGPX", store.directory.appendingPathComponent("walk.gpx").path]
      + extraArguments + store.launchArguments
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
  private func saveAndCloseSummary(_ app: XCUIApplication) {
    app.buttons["Finish"].press(forDuration: 1.6)
    XCTAssertTrue(app.alerts["Finish Walk?"].waitForExistence(timeout: 5))
    app.alerts.buttons["Save"].tap()
    assertSummary(app)
    app.navigationBars.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
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
