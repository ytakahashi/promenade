import SwiftUI

struct StatisticsScreen: View {
  let model: StatisticsModel

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(Text("Statistics", bundle: .module))
    }
    .onAppear { model.load() }
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      ProgressView()
    case .empty:
      NoWalksView()
    case .failed:
      WalksReadFailureView(retry: model.load)
    case .loaded:
      ScrollView {
        VStack(spacing: 20) {
          StatisticsControls(model: model)
          if let statistics = model.statistics {
            StatisticsSummaryCard(
              statistics: statistics, calendar: model.calendar, metric: model.metric,
              setMetric: model.setMetric)
          }
          AllTimeCard(totals: model.allTime)
        }
        .padding()
      }
      .background(Color(.systemGroupedBackground))
    }
  }
}
