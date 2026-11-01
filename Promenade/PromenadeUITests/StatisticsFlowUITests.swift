import XCTest

final class StatisticsFlowUITests: XCTestCase {
  private var store: UITestStore!

  override func setUpWithError() throws {
    continueAfterFailure = false
    store = try UITestStore()
  }

  override func tearDownWithError() throws {
    store.remove()
  }

  @MainActor
  func testEmptyStatisticsShowsNoWalks() {
    let app = launch(seed: false)
    XCTAssertTrue(app.staticTexts["No Walks Yet"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.segmentedControls.firstMatch.exists)
  }

  @MainActor
  func testPeriodsMetricsSelectionAndAllTime() {
    let app = launch()
    let period = app.segmentedControls.element(boundBy: 0)
    let metric = app.segmentedControls.element(boundBy: 1)
    XCTAssertTrue(period.waitForExistence(timeout: 5))
    XCTAssertTrue(period.buttons["Week"].isSelected)
    XCTAssertTrue(app.staticTexts["Total"].exists)
    XCTAssertFalse(app.buttons["Next period"].isEnabled)
    let chart = app.descendants(matching: .any)["statistics.chart"].firstMatch
    XCTAssertTrue(chart.exists)
    attachScreenshot(app, name: "Statistics week")
    // Selection must work in a chart embedded in a vertically scrolling screen.
    chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    waitForValue(of: chart, matching: hasSelection)
    attachScreenshot(app, name: "Statistics selected bucket")
    let initialSelection = chart.value as? String ?? ""
    chart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
    waitForValue(
      of: chart, matching: NSPredicate(format: "value != '' AND value != %@", initialSelection))
    chart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
    waitForValue(of: chart, matching: hasNoSelection)
    chart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
    waitForValue(of: chart, matching: hasSelection)
    metric.buttons["Steps"].tap()
    waitForValue(of: chart, matching: hasNoSelection)
    metric.buttons["Duration"].tap()
    for title in ["Month", "Year", "Week"] {
      period.buttons[title].tap()
      XCTAssertTrue(period.buttons[title].isSelected)
      XCTAssertTrue(chart.exists)
      attachScreenshot(app, name: "Statistics \(title)")
    }
    app.buttons["Previous period"].tap()
    XCTAssertTrue(app.buttons["Next period"].isEnabled)
    app.buttons["Next period"].tap()
    XCTAssertFalse(app.buttons["Next period"].isEnabled)
    chart.swipeUp()
    XCTAssertTrue(app.staticTexts["All Time"].isHittable)
  }

  @MainActor
  func testDayWalkOpensSharedDetailAndReturnsToStatistics() {
    let app = launch()
    app.segmentedControls.element(boundBy: 0).buttons["Day"].tap()
    // The seed may have no finished walk today. Find an actual recorded day rather than
    // depending on the wall-clock launch time or the seeder's random daily count.
    let row = app.buttons["statistics.walk"].firstMatch
    for _ in 0..<14 {
      app.swipeUp()
      if row.exists { break }
      app.swipeDown()
      app.buttons["Previous period"].tap()
    }
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    attachScreenshot(app, name: "Statistics day walks")
    row.tap()
    XCTAssertTrue(app.navigationBars["Walk"].waitForExistence(timeout: 5))
    // Seed sessions have no route points, so only navigation is checked here.
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Statistics"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.segmentedControls.element(boundBy: 0).buttons["Day"].isSelected)
  }

  private var hasSelection: NSPredicate { NSPredicate(format: "value != nil AND value != ''") }
  private var hasNoSelection: NSPredicate { NSPredicate(format: "value == nil OR value == ''") }

  /// The accessibility value is not guaranteed to be updated as soon as a tap returns.
  @MainActor
  private func waitForValue(
    of element: XCUIElement, matching predicate: NSPredicate, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 3), .completed, file: file, line: line)
  }

  @MainActor
  private func attachScreenshot(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  private func launch(seed: Bool = true) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = store.launchArguments + (seed ? ["-SeedSessions", "60"] : [])
    app.launch()
    let tab = app.tabBars.buttons["Statistics"]
    XCTAssertTrue(tab.waitForExistence(timeout: 10))
    tab.tap()
    if !app.navigationBars["Statistics"].waitForExistence(timeout: 5) { tab.tap() }
    XCTAssertTrue(app.navigationBars["Statistics"].waitForExistence(timeout: 10))
    return app
  }
}
