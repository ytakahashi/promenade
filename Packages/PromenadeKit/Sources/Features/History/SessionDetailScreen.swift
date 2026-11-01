import Domain
import SwiftUI

/// A saved walk opened from History or Statistics; the same content as the post-walk summary.
struct SessionDetailScreen: View {
  @State private var model: SessionSummaryModel

  init(model: SessionSummaryModel) {
    _model = State(initialValue: model)
  }

  var body: some View {
    SessionSummaryView(model: model)
      .navigationTitle(Text("Walk", bundle: .module))
      .navigationBarTitleDisplayMode(.inline)
  }
}
