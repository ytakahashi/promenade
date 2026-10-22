import Foundation
import Testing

@testable import Features

@MainActor
struct MetricFormattingTests {
  @Test(arguments: ["ja_JP", "en_JP", "en_US@measure=metric"])
  func metricSelection(_ identifier: String) {
    #expect(MetricFormatting(locale: Locale(identifier: identifier)).distanceUnit == .kilometers)
  }

  @Test(arguments: ["en_US", "en_GB", "ja_US", "en_GB@measure=uksystem"])
  func mileSelection(_ identifier: String) {
    #expect(MetricFormatting(locale: Locale(identifier: identifier)).distanceUnit == .miles)
  }

  @Test func distanceKeepsSelectedUnitsAtEveryScale() {
    let metric = MetricFormatting(locale: Locale(identifier: "en_US@measure=metric"))
    let miles = MetricFormatting(locale: Locale(identifier: "en_US"))
    #expect(metric.distance(0) == "0.00 km")
    #expect(metric.distance(50) == "0.05 km")
    #expect(metric.distance(1000) == "1.00 km")
    #expect(metric.distance(1234.56) == "1.23 km")
    #expect(miles.distance(0) == "0.00 mi")
    #expect(miles.distance(50) == "0.03 mi")
    #expect(miles.distance(1609.344) == "1.00 mi")
  }

  @Test func paceUsesRawDistanceAndWalkingTime() {
    let formatting = MetricFormatting(locale: Locale(identifier: "en_US@measure=metric"))
    #expect(formatting.pace(secondsPerMeter: 0.6, distance: 49.999) == "--")
    #expect(formatting.pace(secondsPerMeter: 0.6, distance: 50) == "10:00 /km")
    #expect(formatting.pace(secondsPerMeter: 0.6, distance: 0) == "--")
    #expect(formatting.pace(secondsPerMeter: nil, distance: 50) == "--")
    #expect(formatting.pace(secondsPerMeter: 0, distance: 50) == "--")
  }

  @Test func paceConversionAndRounding() {
    let metric = MetricFormatting(locale: Locale(identifier: "en_US@measure=metric"))
    let miles = MetricFormatting(locale: Locale(identifier: "en_GB"))
    #expect(metric.pace(secondsPerMeter: 0.35949, distance: 1000) == "5:59 /km")
    #expect(metric.pace(secondsPerMeter: 0.3595, distance: 1000) == "6:00 /km")
    #expect(metric.pace(secondsPerMeter: 3.6, distance: 1000) == "60:00 /km")
    #expect(miles.pace(secondsPerMeter: 0.6, distance: 1000) == "16:06 /mi")
  }

  @Test(arguments: [Double.nan, .infinity, -.infinity, -1, Double.greatestFiniteMagnitude])
  func invalidPaceIsUnavailable(_ value: Double) {
    let formatting = MetricFormatting(locale: Locale(identifier: "en_US"))
    #expect(formatting.pace(secondsPerMeter: value, distance: 1000) == "--")
  }

  @Test func durationDoesNotWrapHours() {
    let formatting = MetricFormatting(locale: Locale(identifier: "en_US"))
    let cases: [(Double, String)] = [
      (0, "0:00"), (59.99, "0:59"), (60, "1:00"), (3599, "59:59"),
      (3600, "1:00:00"), (90_061, "25:01:01"),
    ]
    for (seconds, expected) in cases {
      #expect(formatting.duration(seconds) == expected)
    }
    #expect(formatting.duration(.infinity) == "--")
    #expect(formatting.duration(-1) == "--")
  }

  @Test func accessibilityDescribesDurationsAndPace() {
    let metric = MetricFormatting(locale: Locale(identifier: "ja_JP"))
    #expect(metric.durationAccessibility(90_000).contains("25 hours"))
    #expect(metric.paceAccessibility(secondsPerMeter: 0.6, distance: 50).contains("per kilometer"))
    #expect(metric.paceAccessibility(secondsPerMeter: nil, distance: 50) == "Not available")
  }
}
