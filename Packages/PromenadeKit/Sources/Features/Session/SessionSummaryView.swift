import SwiftUI

/// Loads a saved walk and shows its summary, or a retryable failure. The caller provides the
/// navigation container and title.
struct SessionSummaryView: View {
  let model: SessionSummaryModel
  var trim: SessionTrimDependencies? = nil
  @State private var trimModel: SessionTrimModel?
  @State private var revision = 0

  var body: some View {
    content
      .task(id: revision) { await model.load() }
      .toolbar {
        if let trim, case .loaded(let data) = model.state, data.hasRecordedPoints {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              trimModel = model.makeTrimModel(using: trim)
            } label: {
              Text("Trim", bundle: .module)
            }
            .disabled(!model.canTrim)
            .accessibilityIdentifier("summary.trim")
          }
        }
      }
      .navigationDestination(
        isPresented: Binding(
          get: { trimModel != nil }, set: { if !$0 { trimModel = nil } }
        )
      ) {
        if let trimModel, let trim {
          SessionTrimScreen(model: trimModel) {
            // Returning from a push does not reliably re-run the stack's onAppear.
            // Explicitly invalidate this summary and refresh both saved-walk collections.
            revision += 1
            trim.saved()
          }
        }
      }
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      ProgressView()
    case .loaded(let data):
      SessionSummaryContent(summary: data.summary)
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
