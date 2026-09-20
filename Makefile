BUNDLE_ID  := com.sidler.githubmonitor
APP        := .build/GitHubMonitor.app
CONFIG     ?= debug
BIN        := .build/$(CONFIG)/GitHubMonitor

.PHONY: all build bundle run test clean kill

all: bundle

build:
	swift build -c $(CONFIG)

# Assemble a proper .app bundle and ad-hoc sign it. The signature plus the
# stable bundle identifier is what keeps the Keychain entry reachable across
# rebuilds -- see README.
bundle: build
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	@cp "$(BIN)" "$(APP)/Contents/MacOS/GitHubMonitor"
	@codesign --force --sign - --identifier $(BUNDLE_ID) "$(APP)"
	@echo "built $(APP)"

run: kill bundle
	@open "$(APP)"

# The app has no Dock icon, so a plain relaunch would silently stack instances.
kill:
	@pkill -x GitHubMonitor 2>/dev/null || true

# Without a full Xcode install, the swift-testing macro plugin sits in a
# subdirectory SwiftPM does not search by default. Point at it explicitly.
TESTING_PLUGINS := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

test:
	swift test $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS),)

clean:
	rm -rf .build
