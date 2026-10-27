import Domain
import SwiftUI

enum StatisticsMetric: CaseIterable {
  case distance, steps, duration

  var title: Text {
    switch self {
    case .distance: Text("Distance", bundle: .module)
    case .steps: Text("Steps", bundle: .module)
    case .duration: Text("Duration", bundle: .module)
    }
  }

  func value(in totals: MetricTotals) -> Double? {
    switch self {
    case .distance: totals.distance
    case .steps: totals.steps.map(Double.init)
    case .duration: totals.walkingDuration
    }
  }

  func value(in averages: MetricAverages) -> Double? {
    switch self {
    case .distance: averages.distance
    case .steps: averages.steps
    case .duration: averages.walkingDuration
    }
  }
}

extension StatisticsGranularity {
  var title: Text {
    switch self {
    case .day: Text("Day", bundle: .module)
    case .week: Text("Week", bundle: .module)
    case .month: Text("Month", bundle: .module)
    case .year: Text("Year", bundle: .module)
    }
  }
}
