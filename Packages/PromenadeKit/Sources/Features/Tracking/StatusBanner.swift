import SwiftUI

struct StatusBanner: View {
  let content: StatusBannerContent
  let isWorking: Bool
  let retry: () -> Void
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: symbol)
          .foregroundStyle(tint)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: title).font(.subheadline.weight(.semibold))
          if let message {
            Text(verbatim: message)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
      }
      if hasActions {
        HStack(spacing: 12) {
          if canRetry {
            Button(action: retry) {
              if isWorking { ProgressView() } else { Text("Retry", bundle: .module) }
            }
            .disabled(isWorking)
          }
          if opensSettings { OpenSettingsButton() }
          if canDismiss {
            Button(action: dismiss) { Text("Dismiss", bundle: .module) }
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .onChange(of: content, initial: true) {
      // Status changes happen without user interaction, so VoiceOver users are told explicitly.
      AccessibilityNotification.Announcement(title).post()
    }
  }

  private var hasActions: Bool { canRetry || opensSettings || canDismiss }

  private var canRetry: Bool {
    switch content {
    case .waitingForAccess, .updatesStopped, .pointsUnsaved: true
    case .searching, .startFailed, .failed: false
    }
  }

  private var opensSettings: Bool {
    switch content {
    case .waitingForAccess(let issue): issue != .servicesDisabled
    default: false
    }
  }

  private var canDismiss: Bool {
    switch content {
    // A persistence failure that flushing cannot clear must not stay on screen indefinitely.
    case .pointsUnsaved, .startFailed, .failed: true
    case .waitingForAccess, .updatesStopped, .searching: false
    }
  }

  private var symbol: String {
    switch content {
    case .searching: "location.magnifyingglass"
    case .waitingForAccess: "location.slash.fill"
    case .updatesStopped, .pointsUnsaved, .startFailed, .failed: "exclamationmark.triangle.fill"
    }
  }

  private var tint: Color { content == .searching ? .secondary : .orange }

  private var title: String {
    switch content {
    case .waitingForAccess:
      String(localized: "Recording Interrupted", bundle: .module)
    case .updatesStopped:
      String(localized: "Location Updates Stopped", bundle: .module)
    case .pointsUnsaved:
      String(localized: "Some Locations Are Not Saved", bundle: .module)
    case .searching:
      String(localized: "Searching for GPS Signal", bundle: .module)
    case .startFailed:
      String(localized: "Unable to Start Walk", bundle: .module)
    case .failed(let failure):
      failure.message
    }
  }

  private var message: String? {
    switch content {
    case .waitingForAccess(.denied):
      String(
        localized: "Location access was turned off. Recording resumes when access returns.",
        bundle: .module)
    case .waitingForAccess(.servicesDisabled):
      String(
        localized:
          "Location Services were turned off. Turn them on in Settings > Privacy & Security > Location Services to resume.",
        bundle: .module)
    case .waitingForAccess(.accuracyLimited):
      String(
        localized: "Precise location was turned off. Recording resumes when it is allowed again.",
        bundle: .module)
    case .updatesStopped:
      String(localized: "Retry to continue recording your route.", bundle: .module)
    case .pointsUnsaved:
      String(localized: "Recording continues. Retry to save them now.", bundle: .module)
    case .searching:
      String(localized: "Walking time keeps counting.", bundle: .module)
    case .startFailed(let failure):
      failure.message
    case .failed:
      nil
    }
  }
}

#Preview {
  ScrollView {
    VStack(spacing: 12) {
      let contents: [StatusBannerContent] = [
        .waitingForAccess(.denied), .waitingForAccess(.servicesDisabled), .updatesStopped,
        .pointsUnsaved, .searching, .startFailed(.sensor), .failed(.persistence),
      ]
      ForEach(contents.indices, id: \.self) {
        StatusBanner(content: contents[$0], isWorking: false, retry: {}, dismiss: {})
      }
    }
    .padding()
  }
}
