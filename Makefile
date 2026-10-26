SIMULATOR ?= iPhone 17
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)
SOURCES := Promenade Packages

.PHONY: build build-release test test-app test-ui format lint

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

# The package targets iOS only, so tests run on a simulator via xcodebuild instead of `swift test`.
test:
	cd Packages/PromenadeKit && xcodebuild test -scheme PromenadeKit -destination '$(DESTINATION)' -quiet

# App-hosted unit tests and UI tests are intentionally separate from package tests.
test-app:
	xcodebuild test -project Promenade/Promenade.xcodeproj -scheme Promenade -destination '$(DESTINATION)' -only-testing:PromenadeTests -quiet

test-ui:
	xcodebuild test -project Promenade/Promenade.xcodeproj -scheme Promenade -destination '$(DESTINATION)' -only-testing:PromenadeUITests -quiet

format:
	swift format --in-place --recursive $(SOURCES)

lint:
	swift format lint --strict --recursive $(SOURCES)
