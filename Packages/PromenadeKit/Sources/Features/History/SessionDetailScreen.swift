import Domain
import SwiftUI

/// A saved walk opened from History or Statistics; the same content as the post-walk summary.
struct SessionDetailScreen: View {
  @State private var model: SessionSummaryModel
  let trim: SessionTrimDependencies?

  init(model: SessionSummaryModel, trim: SessionTrimDependencies? = nil) {
    self.trim = trim
    _model = State(initialValue: model)
  }

  var body: some View {
    SessionSummaryView(model: model, trim: trim)
      .navigationTitle(Text("Walk", bundle: .module))
      .navigationBarTitleDisplayMode(.inline)
  }
}
