import SwiftUI

nonisolated public enum StartupFailureKind: Sendable, Equatable {
  case storage
  case recovery
  /// Location setup failed for a reason other than Replay options or data.
  case sensors
  case replayArguments
  case replayFile
  case replayData
  case storeArguments
}

public struct StartupFailureView: View {
  private let kind: StartupFailureKind
  private let detail: String
  private let retry: () -> Void

  public init(kind: StartupFailureKind, detail: String, retry: @escaping () -> Void) {
    self.kind = kind
    self.detail = detail
    self.retry = retry
  }

  public var body: some View {
    ContentUnavailableView {
      Label {
        title
      } icon: {
        Image(systemName: "exclamationmark.triangle")
      }
    } description: {
      Text(verbatim: detail)
    } actions: {
      Button(action: retry) { Text("Retry", bundle: .module) }
        .buttonStyle(.borderedProminent)
    }
  }

  private var title: Text {
    switch kind {
    case .storage: Text("Unable to Open Saved Walks", bundle: .module)
    case .recovery: Text("Unable to Read Unfinished Walks", bundle: .module)
    case .sensors: Text("Unable to Set Up Location", bundle: .module)
    case .replayArguments: Text("Invalid Replay Options", bundle: .module)
    case .replayFile: Text("Unable to Read Replay File", bundle: .module)
    case .replayData: Text("Invalid Replay Data", bundle: .module)
    case .storeArguments: Text("Invalid Storage Options", bundle: .module)
    }
  }
}
