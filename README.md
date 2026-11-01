# Promenade

A personal iOS app that records walking routes with GPS and visualizes walking statistics. All data stays on the device.

- **Requirements:** Xcode 26+, iOS 26+ (iPhone)
- **Structure:** `Promenade/` is the Xcode project; `Packages/PromenadeKit/` holds all app logic (`Features → Tracking → (Sensors, Persistence) → Domain`)
- **Build:** `make build`, `make build-release` (also checks that Debug-only launch options are excluded)
- **Test:** `make test` (package), `make test-app` (app-hosted), `make test-ui` (UI); change the simulator with `SIMULATOR="iPhone 17 Pro"`
- **Format:** `make format`, `make lint` (swift-format defaults, no configuration file)
- **Debug launch options:** `-ReplayGPX`, `-ReplaySpeed`, `-ReplaySteps`, `-StoreURL`, `-SeedSessions`
