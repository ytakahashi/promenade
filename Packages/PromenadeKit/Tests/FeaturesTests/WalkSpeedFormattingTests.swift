import Foundation
import Testing

@testable import Features

@MainActor
struct WalkSpeedFormattingTests {
  @Test(arguments: ["ja_JP", "en_US@measure=metric", "en_GB@measure=metric"])
  func metricLocalesUseMetersPerMinute(identifier: String) {
    let formatting = WalkSpeedFormatting(locale: Locale(identifier: identifier))
    #expect(formatting.unit == "m/min")
    #expect(formatting.chartValue(1) == 60)
    #expect(formatting.chartValue(0) == 0)
    #expect(formatting.value(0) == "0 m/min")
  }

  @Test(arguments: ["en_US", "en_GB"])
  func mileLocalesUseFeetPerMinute(identifier: String) {
    let formatting = WalkSpeedFormatting(locale: Locale(identifier: identifier))
    #expect(formatting.unit == "ft/min")
    #expect(abs(formatting.chartValue(1) - 196.8503937007874) < 1e-9)
    #expect(formatting.value(1) == "196.9 ft/min")
  }

  @Test func zeroAndSmallMeasuredSpeedsRemainVisible() {
    let formatting = WalkSpeedFormatting(locale: Locale(identifier: "en_US@measure=metric"))
    #expect(formatting.value(0) == "0 m/min")
    #expect(formatting.value(0.01) == "0.6 m/min")
  }

  @Test func decimalFormattingFollowsTheLocale() {
    let formatting = WalkSpeedFormatting(locale: Locale(identifier: "de_DE"))
    #expect(formatting.value(1.01) == "60,6 m/min")
  }
}
