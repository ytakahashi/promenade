import XCTest

/// Editing flows use Replay and a dedicated persistent store, including across app launches.
final class TrimFlowUITests: XCTestCase {
  private var store: UITestStore!

  override func setUpWithError() throws {
    continueAfterFailure = false
    store = try UITestStore()
    let start = Date(timeIntervalSince1970: 1_767_225_600)
    let formatter = ISO8601DateFormatter()
    // Four meters per second keeps playback short while staying below RouteFilter's speed limit.
    let points = (0..<300).map { index in
      let latitude = 35.68 + Double(index) * 4 / 111_195
      let date = formatter.string(from: start.addingTimeInterval(Double(index)))
      return "<trkpt lat=\"\(latitude)\" lon=\"139.75\"><time>\(date)</time></trkpt>"
    }
    let gpx =
      "<gpx version=\"1.1\" creator=\"Trim UI tests\"><trk><trkseg>"
      + points.joined() + "</trkseg></trk></gpx>"
    try Data(gpx.utf8).write(to: store.directory.appendingPathComponent("walk.gpx"))
  }

  override func tearDownWithError() throws { store.remove() }

  @MainActor
  func testSummaryTrimRefreshesSummaryAndSurvivesRelaunch() {
    let app = recordWalk()
    let original = value(app, id: "summary.distance")
    let expected = chooseEarlierEnd(app)
    XCTAssertNotEqual(expected, original)
    saveTrim(app)
    assertValue(app, id: "summary.distance", equals: expected)
    app.navigationBars.buttons["Done"].tap()
    app.terminate()
    app.launch()
    app.tabBars.buttons["History"].tap()
    let row = app.buttons["history.row"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.tap()
    assertValue(app, id: "summary.distance", equals: expected)
  }

  @MainActor
  func testHistoryTrimRefreshesTheExistingListAndCanEditAgain() {
    let app = recordWalk()
    app.navigationBars.buttons["Done"].tap()
    app.tabBars.buttons["History"].tap()
    let row = app.buttons["history.row"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    let originalRow = row.label + (row.value as? String ?? "")
    row.tap()
    let expected = chooseEarlierEnd(app)
    saveTrim(app)
    assertValue(app, id: "summary.distance", equals: expected)
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    waitFor(
      row,
      predicate: NSPredicate { object, _ in
        guard let row = object as? XCUIElement else { return false }
        return row.label + (row.value as? String ?? "") != originalRow
      })
    row.tap()
    assertValue(app, id: "summary.distance", equals: expected)
    _ = chooseEarlierEnd(app)
    XCTAssertTrue(app.buttons["trim.save"].isEnabled)
    app.navigationBars.buttons.firstMatch.tap()
  }

  @MainActor
  func testStatisticsTrimRefreshesTheCurrentDayWithoutSwitchingTabs() {
    let app = recordWalk()
    app.navigationBars.buttons["Done"].tap()
    app.tabBars.buttons["Statistics"].tap()
    let period = app.segmentedControls.element(boundBy: 0)
    XCTAssertTrue(period.waitForExistence(timeout: 5))
    period.buttons["Day"].tap()
    let row = app.buttons["statistics.walk"].firstMatch
    for _ in 0..<3 {
      app.swipeUp()
      if row.exists { break }
      app.swipeDown()
      app.buttons["Previous period"].tap()
    }
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.tap()
    let expected = chooseEarlierEnd(app)
    saveTrim(app)
    assertValue(app, id: "summary.distance", equals: expected)
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Statistics"].waitForExistence(timeout: 5))
    XCTAssertTrue(period.buttons["Day"].isSelected)
    app.swipeDown()
    assertValue(app, id: "statistics.total", equals: expected)
    app.swipeUp()
    let allTime = element(app, id: "statistics.allTime.distance")
    XCTAssertTrue(allTime.waitForExistence(timeout: 5))
    waitFor(
      allTime,
      predicate: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", expected, expected))
  }

  @MainActor
  func testCancellingConfirmationAndLeavingEditorKeepTheWalk() {
    let app = recordWalk()
    let original = value(app, id: "summary.distance")
    _ = chooseEarlierEnd(app)
    app.buttons["trim.save"].tap()
    let alert = app.alerts["Trim Walk?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    alert.buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Trim Walk"].exists)
    app.navigationBars.buttons.firstMatch.tap()
    assertValue(app, id: "summary.distance", equals: original)
  }

  @MainActor
  func testUnmeasuredStepsAreExplainedBeforeSaving() {
    let app = recordWalk(extra: ["-ReplaySteps", "none"])
    let expected = chooseEarlierEnd(app)
    app.buttons["trim.save"].tap()
    let alert = app.alerts["Trim Walk?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    XCTAssertTrue(
      alert.staticTexts.matching(
        NSPredicate(format: "label CONTAINS %@", "Steps will be unavailable.")
      ).firstMatch.exists)
    alert.buttons["Trim"].tap()
    assertValue(app, id: "summary.distance", equals: expected)
    assertValue(app, id: "summary.steps", equals: "Not available")
  }

  @MainActor
  private func recordWalk(extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      store.launchArguments + [
        "-ReplayGPX", store.directory.appendingPathComponent("walk.gpx").path,
        "-AppleLanguages", "(en)", "-AppleLocale", "en_US@measure=metric",
      ] + extra
    app.launch()
    XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
    app.buttons["Start"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
    // Wait on measured distance, not a fixed delay or a particular number of replay callbacks.
    let distance = app.otherElements["Distance"].firstMatch
    waitFor(
      distance,
      predicate: NSPredicate { object, _ in
        guard let value = (object as? XCUIElement)?.value as? String,
          let number = value.split(whereSeparator: { !$0.isNumber && $0 != "." }).first,
          let kilometers = Double(number)
        else { return false }
        return kilometers >= 0.04
      }, timeout: 20)
    app.buttons["Finish"].press(forDuration: 1.6)
    let finish = app.alerts["Finish Walk?"]
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    finish.buttons["Save"].tap()
    XCTAssertTrue(app.buttons["summary.trim"].waitForExistence(timeout: 10))
    return app
  }

  @MainActor
  private func chooseEarlierEnd(_ app: XCUIApplication) -> String {
    let trim = app.buttons["summary.trim"]
    waitFor(trim, predicate: NSPredicate(format: "enabled == true"))
    trim.tap()
    let slider = app.sliders["trim.slider"]
    XCTAssertTrue(slider.waitForExistence(timeout: 10))
    for _ in 0..<3 where !slider.isHittable { app.swipeUp() }
    slider.adjust(toNormalizedSliderPosition: 0.35)
    waitFor(app.buttons["trim.save"], predicate: NSPredicate(format: "enabled == true"))
    let distance = element(app, id: "trim.distance")
    for _ in 0..<3 where !distance.isHittable { app.swipeUp() }
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Trim selection"
    attachment.lifetime = .keepAlways
    add(attachment)
    return value(app, id: "trim.distance")
  }

  @MainActor
  private func saveTrim(_ app: XCUIApplication) {
    app.buttons["trim.save"].tap()
    let alert = app.alerts["Trim Walk?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    alert.buttons["Trim"].tap()
    XCTAssertTrue(app.navigationBars["Trim Walk"].waitForNonExistence(timeout: 10))
  }

  @MainActor
  private func element(_ app: XCUIApplication, id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
  }

  @MainActor
  private func value(_ app: XCUIApplication, id: String) -> String {
    let element = element(app, id: id)
    XCTAssertTrue(element.waitForExistence(timeout: 10))
    return element.value as? String ?? element.label
  }

  @MainActor
  private func assertValue(_ app: XCUIApplication, id: String, equals expected: String) {
    let element = element(app, id: id)
    XCTAssertTrue(element.waitForExistence(timeout: 10))
    waitFor(
      element, predicate: NSPredicate(format: "value == %@ OR label == %@", expected, expected))
  }

  @MainActor
  private func waitFor(_ element: XCUIElement, predicate: NSPredicate, timeout: TimeInterval = 5) {
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout),
      .completed)
  }
}
