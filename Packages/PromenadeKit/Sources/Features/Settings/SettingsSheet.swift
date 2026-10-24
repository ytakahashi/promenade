import SwiftUI

struct SettingsSheet: View {
  let model: SettingsModel
  let locationAccess: LocationAccessState
  let close: () -> Void
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationStack {
      List {
        Section {
          row("Version", Text(verbatim: model.version))
        } header: {
          Text("App", bundle: .module)
        }
        Section {
          row("Location", status(PermissionStatus(locationAccess)))
          row("Motion & Fitness", status(PermissionStatus(model.motion)))
          Button {
            if let url = URL.appSettings { openURL(url) }
          } label: {
            Text("Open Settings", bundle: .module)
          }
        } header: {
          Text("Permissions", bundle: .module)
        } footer: {
          Text(
            "Location records your route. Motion & Fitness counts your steps.", bundle: .module)
        }
      }
      .navigationTitle(Text("Settings", bundle: .module))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(action: close) { Text("Done", bundle: .module) }
        }
      }
    }
    .onAppear { model.refresh() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.refresh() }
    }
  }

  private func row(_ label: LocalizedStringKey, _ value: Text) -> some View {
    LabeledContent {
      value
    } label: {
      Text(label, bundle: .module)
    }
    .accessibilityElement(children: .combine)
  }

  private func status(_ status: PermissionStatus) -> Text {
    switch status {
    case .allowed: Text("Allowed", bundle: .module)
    case .preciseLocationOff: Text("Precise Location Off", bundle: .module)
    case .denied: Text("Denied", bundle: .module)
    case .restricted: Text("Restricted", bundle: .module)
    case .notDetermined: Text("Not Determined", bundle: .module)
    case .locationServicesOff: Text("Location Services Off", bundle: .module)
    case .unavailable: Text("Unavailable", bundle: .module)
    }
  }
}
