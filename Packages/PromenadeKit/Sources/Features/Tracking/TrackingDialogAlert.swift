import SwiftUI
import Tracking

extension View {
  /// Presents `dialog` as an alert. Dismissal itself changes nothing: only the buttons act, and
  /// the alert closes when the state it is derived from changes. An alert is used rather than a
  /// confirmation dialog because the latter can be dismissed by tapping outside it.
  func trackingDialogAlert(
    _ dialog: TrackingDialog?, failure: TrackingFailure?, confirm: @escaping () -> Void,
    cancel: @escaping () -> Void
  ) -> some View {
    modifier(
      TrackingDialogAlert(dialog: dialog, failure: failure, confirm: confirm, cancel: cancel))
  }
}

private struct TrackingDialogAlert: ViewModifier {
  let dialog: TrackingDialog?
  let failure: TrackingFailure?
  let confirm: () -> Void
  let cancel: () -> Void
  /// Keeps the title while the alert animates out after `dialog` becomes nil.
  @State private var shown: TrackingDialog?

  func body(content: Content) -> some View {
    content
      .alert(
        (dialog ?? shown).map(title) ?? Text(verbatim: ""),
        isPresented: Binding(get: { dialog != nil }, set: { _ in }),
        presenting: dialog ?? shown
      ) { dialog in
        Button(action: confirm) { confirmLabel(dialog) }
        Button(role: .cancel, action: cancel) { Text("Cancel", bundle: .module) }
      } message: { dialog in
        message(dialog)
      }
      .onChange(of: dialog, initial: true) { _, new in
        if let new { shown = new }
      }
  }

  private func title(_ dialog: TrackingDialog) -> Text {
    switch dialog {
    case .confirmTransition(.pause): Text("Pause Walk?", bundle: .module)
    case .confirmTransition(.finish): Text("Finish Walk?", bundle: .module)
    case .confirmResume: Text("Resume Walk?", bundle: .module)
    case .retryTransition(.pause, _): Text("Unable to Pause Walk", bundle: .module)
    case .retryTransition(.finish, _): Text("Unable to Finish Walk", bundle: .module)
    case .retryResume: Text("Unable to Resume Walk", bundle: .module)
    }
  }

  private func confirmLabel(_ dialog: TrackingDialog) -> Text {
    switch dialog {
    case .confirmTransition(.pause): Text("Pause", bundle: .module)
    case .confirmTransition(.finish): Text("Finish", bundle: .module)
    case .confirmResume: Text("Resume", bundle: .module)
    case .retryTransition, .retryResume: Text("Retry", bundle: .module)
    }
  }

  @ViewBuilder
  private func message(_ dialog: TrackingDialog) -> some View {
    switch dialog {
    case .confirmTransition(.pause):
      Text("Rest time starts from when you tapped Pause.", bundle: .module)
    case .confirmTransition(.finish):
      Text("Recording stops, and the walk is saved up to when you held Finish.", bundle: .module)
    case .confirmResume:
      Text("Walking time restarts from when you tapped Resume.", bundle: .module)
    case .retryTransition(_, isPaused: false):
      Text(
        "\(failureText) Retry keeps the original time. Cancel to continue recording.",
        bundle: .module)
    case .retryTransition(_, isPaused: true):
      Text(
        "\(failureText) Retry keeps the original time. Cancel to stay paused.", bundle: .module)
    case .retryResume:
      Text(
        "\(failureText) Retry keeps the time you first tapped Resume. Cancel and tap Resume again to start from a new time.",
        bundle: .module)
    }
  }

  private var failureText: String { (failure ?? .persistence).message }
}
