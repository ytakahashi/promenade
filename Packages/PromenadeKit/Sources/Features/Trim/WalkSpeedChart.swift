import Charts
import Domain
import Foundation
import SwiftUI

/// A saved walk's complete speed series. Selection is supplied by the caller, not owned here.
struct WalkSpeedChart: View {
  let content: WalkSpeedChartContent
  let timeZone: TimeZone
  let selectedDate: Date?
  @Environment(\.locale) private var locale

  var body: some View {
    let formatting = WalkSpeedFormatting(locale: locale)
    let times = MetricFormatting(locale: locale)
    Chart {
      ForEach(content.runs) { run in
        ForEach(run.points) { point in
          LineMark(
            x: .value("Time", point.date),
            y: .value("Speed", formatting.chartValue(point.speed)),
            series: .value("Measured interval", run.id)
          )
          .interpolationMethod(.linear)
          .foregroundStyle(Color.accentColor)
          .lineStyle(StrokeStyle(lineWidth: 2))
          // Each interval has two vertices for drawing, but only its start is spoken.
          .accessibilityHidden(!point.id.isMultiple(of: 2))
          .accessibilityLabel(times.dateTime(point.date, in: timeZone))
          .accessibilityValue(formatting.value(point.speed))
        }
      }
      if let selectedDate {
        RuleMark(x: .value("Finish time", selectedDate))
          .foregroundStyle(Color.primary)
          .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
          .accessibilityLabel(Text("Finish time", bundle: .module))
          .accessibilityValue(times.dateTime(selectedDate, in: timeZone))
      }
    }
    .chartXScale(domain: content.range)
    .chartYScale(domain: 0...formatting.chartValue(content.upperBound))
    .chartXAxis {
      AxisMarks(values: axisDates) { value in
        AxisGridLine()
        AxisTick()
        if let date = value.as(Date.self) {
          AxisValueLabel(
            anchor: value.index == 0
              ? .topLeading : (value.index == value.count - 1 ? .topTrailing : .top)
          ) { Text(verbatim: times.time(date, in: timeZone)) }
        }
      }
    }
    .chartYAxisLabel(formatting.unit)
    .environment(\.timeZone, timeZone)
    // Axes share a fixed plot area. Bound their text scaling to prevent overlapping labels;
    // VoiceOver still exposes the full times and values, and surrounding controls scale normally.
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .frame(height: 180)
    // Before the overlay: applied after it, this label would replace the overlay's text in VoiceOver.
    .accessibilityLabel(Text("Walking speed", bundle: .module))
    .accessibilityIdentifier("trim.speedChart")
    .overlay {
      if content.runs.isEmpty {
        Text("Speed unavailable", bundle: .module)
          .font(.subheadline)
          .padding(8)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
      }
    }
  }

  private var axisDates: [Date] {
    let start = content.range.lowerBound
    let end = content.range.upperBound
    let duration = end.timeIntervalSince(start)
    if duration < 120 { return [start, end] }
    return [start, start.addingTimeInterval(duration / 2), end]
  }

}

#if DEBUG
  #Preview("Speed and gaps") {
    previewChart([1, 1.2, nil, nil, 0.7, 0, 0.1])
      .padding()
  }

  #Preview("One interval") { previewChart([0.8]).padding() }
  #Preview("Stationary") { previewChart([0, 0, 0]).padding() }
  #Preview("Unmeasured") { previewChart([nil, nil]).padding() }
  #Preview("Empty") { previewChart([]).padding() }
  #Preview("Large text") {
    previewChart([1, 0, nil, 1.5]).padding()
      .environment(\.dynamicTypeSize, .accessibility5)
  }
  #Preview("Across midnight") {
    previewChart([1, 1.2, 1, nil, 0.5], start: Date(timeIntervalSince1970: 1_793_804_280))
      .padding()
  }

  private func previewChart(
    _ speeds: [Double?], start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)
  ) -> some View {
    WalkSpeedChart(
      content: WalkSpeedChartContent(
        samples: speeds.enumerated().map {
          SpeedSample(start: start.addingTimeInterval(Double($0.offset) * 60), speed: $0.element)
        }, interval: 60, range: start...start.addingTimeInterval(Double(speeds.count) * 60)),
      timeZone: TimeZone(identifier: "Asia/Tokyo")!,
      selectedDate: start.addingTimeInterval(min(30, Double(speeds.count) * 60)))
  }
#endif
