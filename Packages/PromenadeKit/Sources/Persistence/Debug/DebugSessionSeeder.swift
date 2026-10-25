#if DEBUG
  import Domain
  import Foundation
  import SwiftData

  @MainActor
  public enum DebugSessionSeeder {
    public enum SeedError: Error, Equatable, LocalizedError {
      case invalidCount
      case dateUnavailable

      public var errorDescription: String? {
        switch self {
        case .invalidCount: "Seed session count must be positive."
        case .dateUnavailable: "Could not compute dates for seed sessions."
        }
      }
    }

    /// Seeds an empty isolated store. Call before recovery and before recording can begin.
    public static func seed(
      count: Int, container: ModelContainer, now: Date, calendar: Calendar
    ) throws {
      guard count > 0 else { throw SeedError.invalidCount }
      let context = ModelContext(container)
      context.autosaveEnabled = false
      guard try context.fetchCount(FetchDescriptor<WalkingSession>()) == 0 else { return }
      // A zone that always differs from the device's, so traveled walks exist on any simulator.
      var traveledCalendar = calendar
      traveledCalendar.timeZone =
        TimeZone(
          identifier: calendar.timeZone.identifier == "America/Los_Angeles"
            ? "Asia/Tokyo" : "America/Los_Angeles")!
      var random = SeedRandom()
      var remaining = count
      var day = calendar.startOfDay(for: now)
      while remaining > 0 {
        let walks = Int(random.next() % 3)
        let date = calendar.dateComponents([.era, .year, .month, .day], from: day)
        for slot in 0..<walks where remaining > 0 {
          var components = date
          components.hour = (slot == 0 ? 6 : 17) + Int(random.next() % 3)
          components.minute = Int(random.next() % 60)
          // A traveled walk keeps this day's morning or evening on its own zone's wall clock,
          // which is how Statistics and History place it.
          let recordingCalendar = random.next() % 20 == 0 ? traveledCalendar : calendar
          guard let start = recordingCalendar.date(from: components) else {
            throw SeedError.dateUnavailable
          }
          let distance = 1000 + random.fraction() * 7000
          let duration = distance / (1 + random.fraction() * 0.7)
          let end = start.addingTimeInterval(duration)
          guard end <= now else { continue }
          let steps =
            random.next() % 10 == 0 ? nil : Int(duration / 60 * (90 + random.fraction() * 30))
          let session = WalkingSession(
            id: random.uuid(), startDate: start, stateRaw: SessionState.finished.rawValue,
            timeZoneIdentifier: recordingCalendar.timeZone.identifier)
          session.endDate = end
          session.distance = distance
          session.walkingDuration = end.timeIntervalSince(start)
          session.steps = steps
          // No points are generated: detail views recalculate distance as zero. Keeping the
          // current version prevents immediate recomputation; recreate this store after a bump.
          session.derivedDataVersion = DerivedDataVersion.current
          let segment = Segment(id: random.uuid(), index: 0, startDate: start)
          segment.endDate = end
          segment.endReasonRaw = SegmentEndReason.finished.rawValue
          // Detail views derive steps from segments rather than the session's saved total.
          segment.steps = steps
          context.insert(session)
          context.insert(segment)
          session.segments.append(segment)
          remaining -= 1
        }
        if remaining == 0 { break }
        // Move to the previous day's own start, including where midnight does not exist.
        guard let previous = calendar.dateInterval(of: .day, for: day.addingTimeInterval(-1)),
          previous.start < day
        else { throw SeedError.dateUnavailable }
        day = previous.start
      }
      try context.save()
    }
  }

  /// SplitMix64 with explicit sampling keeps dates, metrics and IDs reproducible across launches.
  private struct SeedRandom {
    private var state: UInt64 = 0x5072_6f6d_656e_6164

    mutating func next() -> UInt64 {
      state &+= 0x9e37_79b9_7f4a_7c15
      var value = state
      value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
      value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
      return value ^ (value >> 31)
    }

    mutating func fraction() -> Double { Double(next() >> 11) / 9_007_199_254_740_992 }

    mutating func uuid() -> UUID {
      var bytes = (0..<16).map { _ in UInt8(truncatingIfNeeded: next()) }
      bytes[6] = (bytes[6] & 0x0f) | 0x40
      bytes[8] = (bytes[8] & 0x3f) | 0x80
      return UUID(
        uuid: (
          bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
          bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
  }
#endif
