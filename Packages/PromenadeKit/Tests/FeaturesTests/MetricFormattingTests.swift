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

  @Test func stepsUseLocaleGroupingAndShowUnmeasuredAsDashes() {
    let us = MetricFormatting(locale: Locale(identifier: "en_US"))
    #expect(us.steps(6196) == "6,196")
    #expect(us.steps(0) == "0")
    #expect(us.steps(nil) == "--")
    #expect(us.stepsAccessibility(6196) == "6,196")
    #expect(us.stepsAccessibility(nil) == "Not available")
    #expect(MetricFormatting(locale: Locale(identifier: "de_DE")).steps(6196) == "6.196")
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

  @Test func aggregateDurationTruncatesSecondsAndDoesNotWrapHours() {
    let formatting = MetricFormatting(locale: Locale(identifier: "de_DE"))
    let cases: [(Double, String)] = [
      (0, "0m"), (59.99, "0m"), (60, "1m"), (2820, "47m"),
      (3599.99, "59m"), (16680, "4h 38m"), (360_060, "100h 1m"),
      (4_442_460, "1,234h 1m"),
    ]
    for (seconds, expected) in cases {
      #expect(formatting.aggregateDuration(seconds) == expected)
    }
    for value in [Double.nan, .infinity, -.infinity, -1, .greatestFiniteMagnitude] {
      #expect(formatting.aggregateDuration(value) == "--")
    }
  }

  @Test func accessibilityDescribesDurationsAndPace() {
    let metric = MetricFormatting(locale: Locale(identifier: "ja_JP"))
    #expect(metric.durationAccessibility(90_000).contains("25 hours"))
    #expect(metric.paceAccessibility(secondsPerMeter: 0.6, distance: 50).contains("per kilometer"))
    #expect(metric.paceAccessibility(secondsPerMeter: nil, distance: 50) == "Not available")
  }

  @Test func speedUsesTheSelectedUnitAndThreshold() {
    let metric = MetricFormatting(locale: Locale(identifier: "en_US@measure=metric"))
    let miles = MetricFormatting(locale: Locale(identifier: "en_US"))
    #expect(metric.speed(metersPerSecond: 1.25, distance: 50) == "4.5 km/h")
    #expect(miles.speed(metersPerSecond: 1.25, distance: 50) == "2.8 mph")
    #expect(metric.speed(metersPerSecond: 1.25, distance: 49.999) == "--")
    #expect(metric.speed(metersPerSecond: nil, distance: 1000) == "--")
    #expect(metric.speed(metersPerSecond: .infinity, distance: 1000) == "--")
    #expect(metric.speedAccessibility(metersPerSecond: nil, distance: 1000) == "Not available")
  }

  @Test func dateTimeUsesTheRecordedTimeZone() throws {
    let formatting = MetricFormatting(locale: Locale(identifier: "en_US"))
    let date = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01 00:00 UTC
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let sameZone = formatting.dateTime(date, in: tokyo, deviceTimeZone: tokyo)
    #expect(sameZone.contains("9:00"))
    #expect(!sameZone.contains("GMT"))
    let otherZone = formatting.dateTime(
      date, in: tokyo, deviceTimeZone: try #require(TimeZone(identifier: "Europe/London")))
    #expect(otherZone.hasPrefix(sameZone))
    #expect(otherZone.count > sameZone.count)
  }

  @Test func timeOnlyKeepsTheRecordedTimeAndTravelZoneSuffix() throws {
    let formatting = MetricFormatting(locale: Locale(identifier: "en_US"))
    let date = Date(timeIntervalSince1970: 1_767_225_600)
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let utc = try #require(TimeZone(secondsFromGMT: 0))
    let local = formatting.time(date, in: tokyo, deviceTimeZone: tokyo)
    #expect(local.contains("9:00"))
    #expect(!local.contains("2026"))
    #expect(
      formatting.time(date, in: tokyo, deviceTimeZone: utc)
        == "\(local) \(tokyo.abbreviation(for: date)!)")
  }
}
