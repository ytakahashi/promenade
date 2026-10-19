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
| `make format` | Format sources with swift-format |
| `make lint` | Lint sources with swift-format (strict) |

The simulator can be changed with `make test SIMULATOR="iPhone 17 Pro"`.

Formatting follows the swift-format defaults; there is intentionally no `.swift-format` configuration file.
