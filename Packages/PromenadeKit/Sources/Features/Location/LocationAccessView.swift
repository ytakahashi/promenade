import SwiftUI
import UIKit

/// Explains why recording cannot start normally. Showing it never requests access.
struct LocationAccessView: View {
  let notice: IdleAccessNotice

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label {
        title.font(.headline)
      } icon: {
        Image(systemName: "location.slash.fill").foregroundStyle(.orange)
      }
      message
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if notice.opensSettings {
        OpenSettingsButton().buttonStyle(.bordered)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
  }

  private var title: Text {
    switch notice {
    case .denied: Text("Location Access Is Off", bundle: .module)
    case .restricted: Text("Location Access Is Restricted", bundle: .module)
    case .servicesDisabled: Text("Location Services Are Off", bundle: .module)
    case .approximateOnly: Text("Precise Location Is Off", bundle: .module)
    }
  }

  private var message: Text {
    switch notice {
    case .denied:
      Text("Allow location access for Promenade in Settings to record walks.", bundle: .module)
    case .restricted:
      Text(
        "Location access is restricted on this device, so walks cannot be recorded.",
        bundle: .module)
    case .servicesDisabled:
      // The app can only open its own settings page, not the device-wide switch.
      Text(
        "Turn on Location Services in Settings > Privacy & Security > Location Services to record walks.",
        bundle: .module)
    case .approximateOnly:
      Text(
        "Recording a route needs precise location. Start to allow it for this walk, or turn on Precise Location in Settings.",
        bundle: .module)
    }
  }
}

/// Opens this app's page in the Settings app.
struct OpenSettingsButton: View {
  @Environment(\.openURL) private var openURL

  var body: some View {
    Button {
      if let url = URL.appSettings { openURL(url) }
    } label: {
      Text("Open Settings", bundle: .module)
    }
  }
}

#Preview {
  ScrollView {
    VStack(spacing: 24) {
      ForEach(
        [IdleAccessNotice.denied, .restricted, .servicesDisabled, .approximateOnly], id: \.self
      ) {
        LocationAccessView(notice: $0)
      }
    }
    .padding()
  }
}

extension URL {
  /// This app's page in Settings. No public URL opens the device-wide Location Services switch.
  static var appSettings: URL? { URL(string: UIApplication.openSettingsURLString) }
}
