SIMULATOR ?= iPhone 17
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)
SOURCES := Promenade Packages

.PHONY: build test test-app test-ui format lint

build:
	xcodebuild build -project Promenade/Promenade.xcodeproj -scheme Promenade -destination '$(DESTINATION)' -quiet

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
