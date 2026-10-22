import SwiftUI

/// A button that fires only after being held for `duration`, showing the hold progress.
struct LongPressButton: View {
  let title: LocalizedStringKey
  let systemImage: String
  let accessibilityLabel: LocalizedStringKey
  let accessibilityHint: LocalizedStringKey
  let isEnabled: Bool
  let action: () -> Void
  @State private var progress: Double = 0
  @State private var completions = 0

  static let duration: TimeInterval = 1

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    Label {
      Text(title, bundle: .module)
    } icon: {
      Image(systemName: systemImage)
    }
    .font(.headline)
    .lineLimit(1)
    .minimumScaleFactor(0.6)
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 50)
    .foregroundStyle(isEnabled ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
    .background(alignment: .leading) {
      GeometryReader { geometry in
        Rectangle().fill(.red.opacity(0.3)).frame(width: geometry.size.width * progress)
      }
    }
    .background(.red.opacity(isEnabled ? 0.12 : 0.05))
    .clipShape(shape)
    .overlay { shape.strokeBorder(.red.opacity(isEnabled ? 0.6 : 0.2)) }
    .contentShape(shape)
    .onLongPressGesture(minimumDuration: Self.duration, maximumDistance: 30) {
      // Guard here as well: whether `.disabled` stops custom gestures is not relied upon.
      guard isEnabled else { return }
      completions += 1
      progress = 0
      action()
    } onPressingChanged: { pressing in
      if pressing && isEnabled {
        withAnimation(.linear(duration: Self.duration)) { progress = 1 }
      } else {
        withAnimation(.easeOut(duration: 0.15)) { progress = 0 }
      }
    }
    .sensoryFeedback(.success, trigger: completions)
    .disabled(!isEnabled)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(accessibilityLabel, bundle: .module))
    .accessibilityHint(Text(accessibilityHint, bundle: .module))
    .accessibilityAddTraits(.isButton)
    // VoiceOver cannot perform a timed hold. Activation takes the same path, which still ends in
    // a confirmation dialog.
    .accessibilityAction {
      guard isEnabled else { return }
      action()
    }
  }
}

#Preview {
  VStack {
    LongPressButton(
      title: "Hold to Finish", systemImage: "stop.fill", accessibilityLabel: "Finish",
      accessibilityHint: "Opens a confirmation to finish the walk.", isEnabled: true, action: {})
    LongPressButton(
      title: "Hold to Finish", systemImage: "stop.fill", accessibilityLabel: "Finish",
      accessibilityHint: "Opens a confirmation to finish the walk.", isEnabled: false, action: {})
  }
  .padding()
}
