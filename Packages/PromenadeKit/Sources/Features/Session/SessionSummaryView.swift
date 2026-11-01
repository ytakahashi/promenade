import SwiftUI

/// Loads a saved walk and shows its summary, or a retryable failure. The caller provides the
/// navigation container and title.
struct SessionSummaryView: View {
  let model: SessionSummaryModel

  var body: some View {
    content
      .task { await model.load() }
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      ProgressView()
    case .loaded(let summary):
      SessionSummaryContent(summary: summary)
    case .failed(let failure):
      ContentUnavailableView {
        Label {
          title(failure)
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
      } description: {
        Text("The walk is saved. Retry to read it again.", bundle: .module)
      } actions: {
        Button {
          Task.immediate { await model.load() }
        } label: {
          Text("Retry", bundle: .module)
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  private func title(_ failure: SessionSummaryModel.Failure) -> Text {
    switch failure {
    case .missing: Text("Walk Not Found", bundle: .module)
    case .unfinished: Text("Walk Is Still Being Saved", bundle: .module)
    case .readFailed: Text("Unable to Read Walk", bundle: .module)
    }
  }
}
