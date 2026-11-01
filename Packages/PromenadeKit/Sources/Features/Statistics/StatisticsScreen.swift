import Domain
import SwiftUI

struct StatisticsScreen: View {
  let model: StatisticsModel
  let route: RouteFilter.Configuration
  let readSession: @MainActor (UUID) async throws -> SessionRecord?

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(Text("Statistics", bundle: .module))
        .navigationDestination(for: UUID.self) { id in
          SessionDetailScreen(
            model: SessionSummaryModel(sessionID: id, route: route, read: readSession))
        }
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
              setMetric: model.setMetric, selectedBucketStart: model.selectedBucketStart,
              toggleBucket: model.toggleBucket)
            if model.granularity == .day {
              StatisticsDayList(entries: statistics.entries, itemsByID: model.itemsByID)
            }
          }
          AllTimeCard(totals: model.allTime)
        }
        .padding()
      }
      .background(Color(.systemGroupedBackground))
    }
  }
}
