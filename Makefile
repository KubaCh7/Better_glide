# BetterGlide — convenience targets. Requires Xcode 26+ and XcodeGen (`brew install xcodegen`).
PROJECT  := BetterGlide.xcodeproj
DERIVED  := build
DEBUG    := $(DERIVED)/Build/Products/Debug
RELEASE  := $(DERIVED)/Build/Products/Release
XCB      := xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED) -quiet

.PHONY: project build release test probe run install dmg clean

$(PROJECT): project.yml
	xcodegen generate

project: $(PROJECT)

build: $(PROJECT)
	$(XCB) -scheme BetterGlide -configuration Debug build

release: $(PROJECT)
	$(XCB) -scheme BetterGlide -configuration Release build

test: $(PROJECT)
	$(XCB) -scheme BetterGlide -configuration Debug -destination 'platform=macOS' test

# Stage (a) prototype: logs finger counts and swipes. Usage: make probe [FINGERS=4]
FINGERS ?= 3
probe: $(PROJECT)
	$(XCB) -scheme SwipeProbe -configuration Debug build
	$(DEBUG)/SwipeProbe $(FINGERS)

run: build
	open $(DEBUG)/BetterGlide.app

# Installing to /Applications keeps the Accessibility grant stable between launches
# and is required for reliable launch-at-login.
install: release
	rm -rf /Applications/BetterGlide.app
	cp -R $(RELEASE)/BetterGlide.app /Applications/
	open /Applications/BetterGlide.app

dmg: release
	scripts/make-dmg.sh $(RELEASE)/BetterGlide.app $(DERIVED)/BetterGlide.dmg

clean:
	rm -rf $(DERIVED) $(PROJECT)
