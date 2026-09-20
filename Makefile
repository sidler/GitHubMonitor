BUNDLE_ID  := com.sidler.githubmonitor
SIGN_NAME  := GitHub Monitor Dev
APP        := .build/GitHubMonitor.app
CONFIG     ?= debug
BIN        := .build/$(CONFIG)/GitHubMonitor

.PHONY: all build bundle run install uninstall test clean kill

all: bundle

build:
	swift build -c $(CONFIG)

# Sign with the self-signed development certificate when it exists, otherwise
# fall back to ad-hoc. An ad-hoc signature is not an identity: Little Snitch
# and the Keychain treat every rebuild as a new application.
# Create the certificate once with Scripts/create-signing-certificate.sh.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null | grep "$(SIGN_NAME)" | head -1 | awk '{print $$2}')

# Assemble a proper .app bundle and sign it.
bundle: build
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	@cp "$(BIN)" "$(APP)/Contents/MacOS/GitHubMonitor"
	@codesign --force --sign $(if $(SIGN_ID),$(SIGN_ID),-) --identifier $(BUNDLE_ID) "$(APP)"
	@echo "built $(APP) $(if $(SIGN_ID),(signed as '$(SIGN_NAME)'),(ad-hoc — run Scripts/create-signing-certificate.sh for a stable identity))"

run: kill bundle
	@open "$(APP)"

# Install into /Applications. Worth doing before enabling "launch at login":
# the login item records the app's path, so an app living in .build/ loses its
# entry on the next clean.
INSTALLED := /Applications/GitHubMonitor.app

install: bundle
	@pkill -x GitHubMonitor 2>/dev/null || true
	@rm -rf "$(INSTALLED)"
	@cp -R "$(APP)" "$(INSTALLED)"
	@echo "installed $(INSTALLED)"
	@echo "If 'launch at login' was already on, switch it off and on again so"
	@echo "the login item points at the new location."
	@open "$(INSTALLED)"

uninstall:
	@pkill -x GitHubMonitor 2>/dev/null || true
	@rm -rf "$(INSTALLED)"
	@echo "removed $(INSTALLED)"

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
