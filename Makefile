SIMULATOR ?= iPhone 17
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)
SOURCES := Promenade Packages
# Extra xcodebuild test arguments, e.g. a result bundle path in CI.
XCODEBUILD_ARGS ?=

.PHONY: build build-release boot-simulator test test-app test-ui format lint

build:
	xcodebuild build -project Promenade/Promenade.xcodeproj -scheme Promenade -destination '$(DESTINATION)' -quiet

# Debug-only launch options (Replay and the UI test store) must not reach Release. Searching the
# whole bundle also covers code linked from the package.
build-release:
	xcodebuild build -project Promenade/Promenade.xcodeproj -scheme Promenade -configuration Release -destination '$(DESTINATION)' -quiet
	@app="$$(xcodebuild -project Promenade/Promenade.xcodeproj -scheme Promenade -configuration Release -destination '$(DESTINATION)' -showBuildSettings 2>/dev/null | awk -F' = ' '/ TARGET_BUILD_DIR = /{d=$$2} / WRAPPER_NAME = /{w=$$2} END{print d"/"w}')"; \
	if grep -rlaE -- '-(ReplayGPX|ReplaySpeed|ReplaySteps|StoreURL|SeedSessions)' "$$app"; then \
		echo "Release build contains Debug-only launch options" >&2; exit 1; \
	fi; \
	echo "Release build has no Debug-only launch options: $$app"

# Boots the simulator tests use. A name can match several OS versions on CI images: runtimes are
# listed oldest first, and xcodebuild picks the newest for a name-only destination.
boot-simulator:
	@udid="$$(xcrun simctl list devices available | grep -E '^ +$(SIMULATOR) \(' | tail -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"; \
	if [ -z "$$udid" ]; then echo "Simulator not found: $(SIMULATOR)" >&2; exit 1; fi; \
	echo "Booting $(SIMULATOR): $$udid"; \
	xcrun simctl bootstatus "$$udid" -b

# The package targets iOS only, so tests run on a simulator via xcodebuild instead of `swift test`.
test:
	cd Packages/PromenadeKit && xcodebuild test -scheme PromenadeKit -destination '$(DESTINATION)' -quiet $(XCODEBUILD_ARGS)

# App-hosted unit tests and UI tests are intentionally separate from package tests.
test-app:
	xcodebuild test -project Promenade/Promenade.xcodeproj -scheme Promenade -destination '$(DESTINATION)' -only-testing:PromenadeTests -quiet $(XCODEBUILD_ARGS)

test-ui:
	xcodebuild test -project Promenade/Promenade.xcodeproj -scheme Promenade -destination '$(DESTINATION)' -only-testing:PromenadeUITests -quiet $(XCODEBUILD_ARGS)

format:
	swift format --in-place --recursive $(SOURCES)

lint:
	swift format lint --strict --recursive $(SOURCES)
