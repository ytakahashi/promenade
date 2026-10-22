import SwiftUI
import Tracking

enum TrackingControlState: Equatable {
  case start
  /// Launch recovery has loaded a session but the engine has not decided how to continue it.
  case restoring
  case recording
  case paused
  /// The recovery decision is presented elsewhere, or access must be fixed in Settings first.
  case hidden

  /// - Parameter startAllowed: false when location access cannot be obtained by starting.
  init(phase: TrackingPhase, hasLiveSession: Bool, startAllowed: Bool = true) {
    switch phase {
    // During recovery the phase stays idle with a live session; Start would do nothing then.
    case .idle where hasLiveSession: self = .restoring
    case .idle: self = startAllowed ? .start : .hidden
    case .recording: self = .recording
    case .paused: self = .paused
    case .awaitingRecoveryDecision: self = .hidden
    }
  }
}

struct TrackingControls: View {
  let state: TrackingControlState
  let isEnabled: Bool
  let isWorking: Bool
  let start: () -> Void
  let pause: () -> Void
  let resume: () -> Void
  let finish: () -> Void

  var body: some View {
    switch state {
    case .start:
      primaryButton("Start", systemImage: "play.fill", action: start)
    case .restoring:
      HStack(spacing: 8) {
        ProgressView()
        Text("Restoring walk", bundle: .module)
      }
      .frame(minHeight: 50)
    case .recording:
      HStack(spacing: 12) {
        primaryButton("Pause", systemImage: "pause.fill", action: pause)
        finishButton
      }
    case .paused:
      HStack(spacing: 12) {
        primaryButton("Resume", systemImage: "play.fill", action: resume)
        finishButton
      }
    case .hidden:
      EmptyView()
    }
  }

  private var finishButton: some View {
    LongPressButton(
      title: "Hold to Finish", systemImage: "stop.fill", accessibilityLabel: "Finish",
      accessibilityHint: "Opens a confirmation to finish the walk.", isEnabled: isEnabled,
      action: finish)
  }

  private func primaryButton(
    _ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label {
        Text(title, bundle: .module)
      } icon: {
        if isWorking {
          ProgressView()
        } else {
          Image(systemName: systemImage)
        }
      }
      .font(.headline)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .frame(maxWidth: .infinity, minHeight: 34)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .disabled(!isEnabled)
  }

}

extension TrackingFailure {
  var message: String {
    switch self {
    case .access: String(localized: "Location access is unavailable.", bundle: .module)
    case .sensor: String(localized: "Location updates are unavailable.", bundle: .module)
    case .persistence: String(localized: "The walk could not be saved.", bundle: .module)
    }
  }
}

#Preview("States") {
  ScrollView {
    VStack(spacing: 24) {
      ForEach(
        [TrackingControlState.start, .restoring, .recording, .paused], id: \.self
      ) { state in
        TrackingControls(
          state: state, isEnabled: true, isWorking: false, start: {}, pause: {}, resume: {},
          finish: {})
      }
    }
  }
}

#Preview("Busy, large text") {
  TrackingControls(
    state: .paused, isEnabled: false, isWorking: true, start: {}, pause: {}, resume: {},
    finish: {}
  )
  .environment(\.dynamicTypeSize, .accessibility5)
}
