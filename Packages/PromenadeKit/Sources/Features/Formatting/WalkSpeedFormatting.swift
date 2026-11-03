import Foundation

/// Formatting for interval speeds, independent of the summary's average-speed display threshold.
struct WalkSpeedFormatting {
  let locale: Locale

  var unit: String { usesFeet ? "ft/min" : "m/min" }

  func chartValue(_ metersPerSecond: Double) -> Double {
    let metersPerMinute = metersPerSecond * 60
    return usesFeet
      ? Measurement(value: metersPerMinute, unit: UnitLength.meters).converted(to: .feet).value
      : metersPerMinute
  }

  func value(_ metersPerSecond: Double) -> String {
    let number = chartValue(metersPerSecond).formatted(
      .number.precision(.fractionLength(0...1)).locale(locale))
    return "\(number) \(unit)"
  }

  private var usesFeet: Bool { MetricFormatting(locale: locale).distanceUnit == .miles }
}
