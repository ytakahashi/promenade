import SwiftUI

/// Tells the user that launch recovery finished a stale walk on its own.
struct AutoFinishToast: View {
  let dismiss: () -> Void

  static let displayDuration: Duration = .seconds(6)

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("Previous Walk Finished", bundle: .module)
          .font(.subheadline.weight(.semibold))
        Text(
          "It had no activity for a long time, so it was saved as of its last activity.",
          bundle: .module
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Button(action: dismiss) {
        Image(systemName: "xmark")
      }
      .accessibilityLabel(Text("Dismiss", bundle: .module))
    }
    .padding(12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .shadow(radius: 4, y: 2)
    .accessibilityElement(children: .combine)
    .onAppear {
      AccessibilityNotification.Announcement(
        String(localized: "Previous Walk Finished", bundle: .module)
      ).post()
    }
  }
}

#Preview {
  AutoFinishToast(dismiss: {}).padding()
}
