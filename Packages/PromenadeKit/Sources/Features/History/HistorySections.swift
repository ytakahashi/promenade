import Domain
import Foundation

/// Finished walks of one month, in the time zone each walk was recorded in.
struct HistorySection: Identifiable, Equatable {
  /// `yyyy-MM`, stable across reloads so a section can be scrolled to.
  let id: String
  let year: Int
  let month: Int
  /// Newest first.
  let items: [SessionListItem]

  /// Grouped by the month each walk started in where it was recorded, matching the times shown
  /// in its row and details. Sections and items are newest first.
  static func make(_ items: [SessionListItem]) -> [HistorySection] {
    var groups: [String: (year: Int, month: Int, items: [SessionListItem])] = [:]
    for item in items {
      // Gregorian months share boundaries with the calendars users typically select, so grouping
      // stays correct while titles follow the user's calendar.
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: item.timeZoneIdentifier) ?? .current
      let components = calendar.dateComponents([.year, .month], from: item.startDate)
      guard let year = components.year, let month = components.month else { continue }
      let id = String(format: "%04d-%02d", year, month)
      groups[id, default: (year, month, [])].items.append(item)
    }
    // Walks recorded in different time zones can be out of order across a month boundary.
    return groups.map { id, group in
      HistorySection(
        id: id, year: group.year, month: group.month,
        items: group.items.sorted { $0.startDate > $1.startDate })
    }
    .sorted { $0.id > $1.id }
  }

  /// The month as a title in `locale`, e.g. "October 2026".
  func title(locale: Locale) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 15)) else {
      return id
    }
    var style = Date.FormatStyle(locale: locale).year().month(.wide)
    style.timeZone = calendar.timeZone
    return date.formatted(style)
  }
}
