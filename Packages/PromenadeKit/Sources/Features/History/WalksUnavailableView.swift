import SwiftUI

/// Shown by every screen that lists saved walks when there are none, so the screens agree.
struct NoWalksView: View {
  var body: some View {
    ContentUnavailableView {
      Label {
        Text("No Walks Yet", bundle: .module)
      } icon: {
        Image(systemName: "figure.walk")
      }
    } description: {
      Text("Walks you finish appear here.", bundle: .module)
    }
  }
}

/// Shown by every screen that lists saved walks when reading them fails.
struct WalksReadFailureView: View {
  let retry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label {
        Text("Unable to Read Walks", bundle: .module)
      } icon: {
        Image(systemName: "exclamationmark.triangle")
      }
    } actions: {
      Button(action: retry) {
        Text("Retry", bundle: .module)
      }
      .buttonStyle(.borderedProminent)
    }
  }
}
