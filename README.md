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
without deleting saved walks. Tracking displays segment-separated routes and live walking time,
rest time, distance, and average pace. Recovery decisions are connected in subsequent UI work;
History and Statistics remain placeholders.

Start begins a walk without confirmation. Pause and Resume take effect from the tap, and Finish
from the moment a one-second hold completes; each opens a confirmation first. If saving a confirmed
change fails, Retry reuses the original time, and Cancel keeps the walk in its previous state.
Under VoiceOver, activating Finish opens the same confirmation without the hold.

The map initially follows the device location. Panning preserves the chosen camera until the
current-location button is used. Viewing the map does not request location permission. Distance
and pace use kilometers for metric measurement settings and miles for US/UK settings. Pace is
unavailable below 50 meters, and durations retain hours beyond 24. Time updates are confined to
the metrics panel; they do not rebuild route coordinates.

Features previews cover separate segments, empty/single-point routes, a large route, metric/mile
formatting, large text, and each control state. Replay route points are distinct from MapKit's
device location, so pan to the route when inspecting replayed data.

Launch recovery reserves location resources synchronously, then waits for the first active scene
before choosing the foreground recovery policy. If no scene becomes active within 3 seconds, it
infers a background launch and resumes recording. A location launch option, when supplied, chooses
background recovery immediately; scene-based apps normally do not receive launch options.
The deadline is a heuristic: a slow foreground launch can be classified as background. Sessions
that are paused, expired, or absent do not wait for this classification. An explicit Retry always
uses the foreground policy. The `launch` and `tracking` log categories include a shared launch ID,
the resolution reason, elapsed time, and resource/subscription transitions for device validation.
Normal launches may briefly create location resources before releasing them for recovery consent.
This speculative reservation happens only when location access is already granted, so it never
shows a permission prompt before the user chooses to resume.
OS-triggered background relaunch and possible gaps before subscription require device validation.

Debug builds accept `-ReplayGPX <absolute path>` and optional `-ReplaySpeed <positive finite number>`
as launch arguments. Speed defaults to 1. The file must be readable by the app; on the Simulator,
use an accessible host path. Invalid options, unreadable files, and invalid GPX show an error instead
of falling back to real GPS. Retry rereads the file, so a repaired GPX can be loaded without relaunching.
Replay does not require device location permission. Release builds do not include Replay support.

Replay uses the regular saved-walk store and recovery path. Speed changes both event intervals and
point timestamps; use speed 1 when checking route filtering or time thresholds.

Formatting follows the swift-format defaults; there is intentionally no `.swift-format` configuration file.
