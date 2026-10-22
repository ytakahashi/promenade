import Foundation

struct MetricFormatting {
  enum DistanceUnit: Equatable {
    case kilometers, miles

    var length: UnitLength { self == .kilometers ? .kilometers : .miles }
    var meters: Double { Measurement(value: 1, unit: length).converted(to: .meters).value }
  }

  // This is a presentation threshold; it must not change persisted distance or route filtering.
  // Pace and speed over shorter distances are dominated by GPS noise.
  static let rateDisplayMinimumDistance: Double = 50
  let locale: Locale

  var distanceUnit: DistanceUnit {
    switch locale.measurementSystem {
    case .us, .uk: .miles
    default: .kilometers
    }
  }

  func distance(
    _ meters: Double, width: Measurement<UnitLength>.FormatStyle.UnitWidth = .abbreviated
  )
    -> String
  {
    Measurement(value: meters, unit: UnitLength.meters).converted(to: distanceUnit.length)
      .formatted(
        .measurement(
          width: width, usage: .asProvided,
          numberFormatStyle: .number.precision(.fractionLength(2))
        )
        .locale(locale))
  }

  func duration(_ interval: TimeInterval) -> String {
    guard let seconds = wholeSeconds(interval, rounding: .down) else { return "--" }
    let minutes = seconds / 60
    let remainder = padded(seconds % 60)
    if seconds < 3600 { return "\(minutes):\(remainder)" }
    return "\(seconds / 3600):\(padded(minutes % 60)):\(remainder)"
  }

  func durationAccessibility(_ interval: TimeInterval) -> String {
    guard let seconds = wholeSeconds(interval, rounding: .down) else {
      return String(localized: "Not available", bundle: .module)
    }
    let formatter = DateComponentsFormatter()
    var calendar = Calendar(identifier: .gregorian)
    // The UI is English even when numeric formatting follows a different device locale.
    calendar.locale = Locale(identifier: "en_US")
    formatter.calendar = calendar
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .full
    return formatter.string(from: TimeInterval(seconds)) ?? duration(interval)
  }

  func paceSeconds(secondsPerMeter: Double?, distance: Double) -> Int? {
    guard distance.isFinite, distance >= Self.rateDisplayMinimumDistance,
      let secondsPerMeter, secondsPerMeter.isFinite, secondsPerMeter > 0
    else { return nil }
    // Round total seconds first so a minute boundary can never produce a ":60" suffix.
    return wholeSeconds(secondsPerMeter * distanceUnit.meters, rounding: .toNearestOrAwayFromZero)
  }

  func pace(secondsPerMeter: Double?, distance: Double) -> String {
    guard let seconds = paceSeconds(secondsPerMeter: secondsPerMeter, distance: distance) else {
      return "--"
    }
    let time = "\(seconds / 60):\(padded(seconds % 60))"
    switch distanceUnit {
    case .kilometers: return String(localized: "\(time) /km", bundle: .module)
    case .miles: return String(localized: "\(time) /mi", bundle: .module)
    }
  }

  func paceAccessibility(secondsPerMeter: Double?, distance: Double) -> String {
    guard let seconds = paceSeconds(secondsPerMeter: secondsPerMeter, distance: distance) else {
      return String(localized: "Not available", bundle: .module)
    }
    let time = durationAccessibility(TimeInterval(seconds))
    switch distanceUnit {
    case .kilometers: return String(localized: "\(time) per kilometer", bundle: .module)
    case .miles: return String(localized: "\(time) per mile", bundle: .module)
    }
  }

  func speed(metersPerSecond: Double?, distance: Double) -> String {
    speed(metersPerSecond, distance: distance, width: .abbreviated) ?? "--"
  }

  func speedAccessibility(metersPerSecond: Double?, distance: Double) -> String {
    speed(metersPerSecond, distance: distance, width: .wide)
      ?? String(localized: "Not available", bundle: .module)
  }

  /// Formats `date` in the time zone it was recorded in. The zone is named only when it differs
  /// from the device's, where the wall-clock time alone would be misread.
  func dateTime(_ date: Date, in timeZone: TimeZone, deviceTimeZone: TimeZone = .current) -> String
  {
    var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)
    style.timeZone = timeZone
    let text = date.formatted(style)
    guard timeZone.identifier != deviceTimeZone.identifier else { return text }
    return "\(text) \(timeZone.abbreviation(for: date) ?? timeZone.identifier)"
  }

  private func speed(
    _ metersPerSecond: Double?, distance: Double,
    width: Measurement<UnitSpeed>.FormatStyle.UnitWidth
  ) -> String? {
    guard distance.isFinite, distance >= Self.rateDisplayMinimumDistance,
      let metersPerSecond, metersPerSecond.isFinite, metersPerSecond > 0
    else { return nil }
    let unit: UnitSpeed = distanceUnit == .kilometers ? .kilometersPerHour : .milesPerHour
    return Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
      .converted(to: unit)
      .formatted(
        .measurement(
          width: width, usage: .asProvided,
          numberFormatStyle: .number.precision(.fractionLength(1))
        )
        .locale(locale))
  }

  private func wholeSeconds(_ value: Double, rounding: FloatingPointRoundingRule) -> Int? {
    guard value.isFinite, value >= 0 else { return nil }
    return Int(exactly: value.rounded(rounding))
  }

  private func padded(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }
}
