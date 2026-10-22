import SwiftUI
import Tracking

extension View {
  /// Asks how to continue a walk interrupted by termination. There is deliberately no Cancel: the
  /// walk cannot be recorded or started anew until the user decides. The alert is derived from
  /// the engine phase, so it returns after a failed choice or a visit to Settings.
  func recoveryAlert(
    _ dialog: RecoveryDialog?, resume: @escaping () -> Void, finish: @escaping () -> Void
  ) -> some View {
    modifier(RecoveryAlert(dialog: dialog, resume: resume, finish: finish))
  }
}

private struct RecoveryAlert: ViewModifier {
  let dialog: RecoveryDialog?
  let resume: () -> Void
  let finish: () -> Void
  /// Keeps the content while the alert animates out after `dialog` becomes nil.
  @State private var shown: RecoveryDialog?
  @Environment(\.openURL) private var openURL

  func body(content: Content) -> some View {
    content
      .alert(
        Text("Continue Previous Walk?", bundle: .module),
        isPresented: Binding(get: { dialog != nil }, set: { _ in }),
        presenting: dialog ?? shown
      ) { dialog in
        Button(action: resume) { Text("Resume", bundle: .module) }
        Button(action: finish) { Text("Finish", bundle: .module) }
        if dialog.failure.map(Self.opensSettings) == true {
          Button {
            if let url = URL.appSettings { openURL(url) }
          } label: {
            Text("Open Settings", bundle: .module)
          }
        }
      } message: { dialog in
        Text(verbatim: message(dialog))
      }
      .onChange(of: dialog, initial: true) { _, new in
        if let new { shown = new }
      }
  }

  private static func opensSettings(_ failure: TrackingFailure) -> Bool {
    guard case .access(let issue) = failure else { return false }
    return issue != .servicesDisabled
  }

  private func message(_ dialog: RecoveryDialog) -> String {
    let last = dialog.lastActivity
    let time =
      Calendar.current.isDateInToday(last)
      ? last.formatted(date: .omitted, time: .shortened)
      : last.formatted(date: .abbreviated, time: .shortened)
    let explanation = String(
      localized:
        "Recording stopped unexpectedly. The last activity was at \(time). Resume continues this walk from now and counts the time in between as an interruption. Finish saves it as of the last activity.",
      bundle: .module)
    guard let failure = dialog.failure else { return explanation }
    return failure.message + "\n\n" + explanation
  }
}
