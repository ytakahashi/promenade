import Domain
import Foundation
import Testing

@testable import Features

struct WalkSpeedChartContentTests {
  @Test func adjacentAveragesHaveFullWidthsAndVerticalSteps() {
    let content = chart([1, 2])
    #expect(content.runs.count == 1)
    #expect(content.runs[0].points.map(\.date) == [date(0), date(60), date(60), date(120)])
    #expect(content.runs[0].points.map(\.speed) == [1, 1, 2, 2])
    #expect(content.runs[0].points.map(\.id) == [0, 1, 2, 3])
    #expect(content.upperBound == 2.2)
  }

  @Test func nilBinsBreakTheLineAndIsolatedBinsRemainVisible() {
    let content = chart([nil, 1, nil, nil, 2, nil])
    #expect(content.runs.map(\.id) == [0, 1])
    #expect(
      content.runs.map { $0.points.map(\.date) } == [
        [date(60), date(120)], [date(240), date(300)],
      ])
    #expect(content.range == date(0)...date(360))
  }

  @Test func lastBinEndsAtTheSessionEnd() {
    let content = chart([1, 2], duration: 75)
    #expect(content.runs[0].points.map(\.date) == [date(0), date(60), date(60), date(75)])
    #expect(content.range == date(0)...date(75))
  }

  @Test func stationaryValuesAreMeasuredAndHaveANondegenerateAxis() {
    let content = chart([0, 0])
    #expect(content.runs.count == 1)
    #expect(content.runs[0].points.map(\.speed) == [0, 0, 0, 0])
    #expect(content.upperBound == 1)
  }

  @Test func emptyAndUnmeasuredChartsKeepTheWholeTimeRange() {
    for content in [chart([], duration: 120), chart([nil, nil])] {
      #expect(content.runs.isEmpty)
      #expect(content.range == date(0)...date(120))
      #expect(content.upperBound == 1)
    }
    let instant = chart([], duration: 0)
    #expect(instant.runs.isEmpty)
    #expect(instant.range == date(0)...date(1))
  }

  @Test func nonfiniteOrNegativeValuesDoNotReachTheChart() {
    let content = chart([1, .nan, -.infinity, -1, .infinity, 0])
    #expect(content.runs.count == 2)
    #expect(content.runs[1].points.map(\.date) == [date(300), date(360)])
    #expect(content.runs.flatMap(\.points).allSatisfy { $0.speed.isFinite && $0.speed >= 0 })
  }

  @Test func missingIntervalsDoNotConnectEvenWithoutAnExplicitNilSample() {
    let content = WalkSpeedChartContent(
      samples: [.init(start: date(0), speed: 1), .init(start: date(120), speed: 2)],
      interval: 60, range: date(0)...date(180))
    #expect(content.runs.count == 2)
    #expect(content.runs[0].points.last?.date == date(60))
    #expect(content.runs[1].points.first?.date == date(120))
  }

  private func chart(_ speeds: [Double?], duration: Double? = nil) -> WalkSpeedChartContent {
    WalkSpeedChartContent(
      samples: speeds.enumerated().map {
        .init(start: date(Double($0.offset) * 60), speed: $0.element)
      },
      interval: 60, range: date(0)...date(duration ?? Double(speeds.count) * 60))
  }

  private func date(_ seconds: Double) -> Date { TrimFixtures.date(seconds) }
}
