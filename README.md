# Promenade

A personal iOS app that records walking routes with GPS and visualizes daily walking activity.
All data stays on the device.

## Requirements

- Xcode 26 or later
- iOS 26 or later (iPhone)

## Project Structure

```
Promenade/                  Xcode project (app entry point, Info.plist, assets)
Packages/PromenadeKit/      Swift package containing all app logic
  Sources/
    Domain/                 Value types and pure logic (Foundation only)
    Persistence/            SwiftData models, schemas, repositories
    Sensors/                Location and pedometer providers
    Tracking/               Recording state machine
    Features/               SwiftUI screens
  Tests/                    Unit tests (Swift Testing)
```

Module dependencies: `Features → Tracking → (Sensors, Persistence) → Domain`.

## Development

| Command | Description |
|---|---|
| `make build` | Build the app for the iOS Simulator |
| `make test` | Run package unit tests on the iOS Simulator |
| `make test-app` | Run app-hosted unit tests on the iOS Simulator |
| `make test-ui` | Run UI tests on the iOS Simulator |
| `make format` | Format sources with swift-format |
| `make lint` | Lint sources with swift-format (strict) |

The simulator can be changed with `make test SIMULATOR="iPhone 17 Pro"`.

`make test` runs only package tests, including Features tests. It does not run app-hosted or UI tests.

## Launch and Replay

The app creates its dependencies once in `AppDelegate.init` and begins recovery synchronously in
`didFinishLaunching`. Storage or recovery-read failures keep recording unavailable and offer Retry
without deleting saved walks. Recovery decisions and recording controls are connected in subsequent
UI work; the three tabs currently remain placeholders.

Debug builds accept `-ReplayGPX <absolute path>` and optional `-ReplaySpeed <positive finite number>`
as launch arguments. Speed defaults to 1. The file must be readable by the app; on the Simulator,
use an accessible host path. Invalid options, unreadable files, and invalid GPX show an error instead
of falling back to real GPS. Retry rereads the file, so a repaired GPX can be loaded without relaunching.
Replay does not require device location permission. Release builds do not include Replay support.

Replay uses the regular saved-walk store and recovery path. Speed changes both event intervals and
point timestamps; use speed 1 when checking route filtering or time thresholds.

Formatting follows the swift-format defaults; there is intentionally no `.swift-format` configuration file.
