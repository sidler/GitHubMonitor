BUNDLE_ID  := com.sidler.githubmonitor
SIGN_NAME  := GitHub Monitor Dev
APP        := .build/GitHubMonitor.app
CONFIG     ?= debug
BIN        := .build/$(CONFIG)/GitHubMonitor

.PHONY: all build bundle run install uninstall test clean kill icon

# Regenerate the app icon from the SVG. Only needed when the artwork changes;
# the .icns is checked in.
icon:
	@swift Scripts/make-icon.swift Resources/AppIcon.svg /tmp/AppIcon.iconset
	@iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "regenerated Resources/AppIcon.icns"

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
	@Scripts/assemble-bundle.sh "$(APP)" "$(BIN)" "$(BUNDLE_ID)" \
		--sign $(if $(SIGN_ID),$(SIGN_ID),-)
	@echo "built $(APP) $(if $(SIGN_ID),(signed as '$(SIGN_NAME)'),(ad-hoc — run Scripts/create-signing-certificate.sh for a stable identity))"

run: kill bundle
	@open "$(APP)"

# MARK: - Release

# Signing and notarising a build for other people's Macs.
#
# Three things have to be true before `make release` can work, and none of
# them can be arranged from here:
#
#  1. A "Developer ID Application" certificate in the keychain. It comes
#     from the paid Apple Developer Program: create a certificate request
#     in Keychain Access, upload it at developer.apple.com under
#     Certificates, download the .cer and double-click it. The other
#     certificate types do not work -- "Apple Development" is for testing,
#     "Apple Distribution" is for the App Store.
#  2. Notarisation credentials stored under a profile name, once:
#       xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
#         --apple-id <your-apple-id> --team-id <your-team-id> \
#         --password <an app-specific password from appleid.apple.com>
#     The password is app-specific, not your Apple ID password.
#  3. A version worth shipping in Resources/Info.plist.
#
# Signing alone is not enough: since macOS 10.15 an app that is signed but
# not notarised is refused by Gatekeeper with "Apple cannot check it for
# malicious software". Notarising without stapling leaves it needing the
# network on first launch. This target does all three.
DEVELOPER_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep "Developer ID Application" | head -1 | awk '{print $$2}')
NOTARY_PROFILE ?= GitHubMonitor
RELEASE_APP := .build/release-app/GitHubMonitor.app
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ZIP := .build/release-app/GitHubMonitor-$(VERSION).zip

.PHONY: release release-sign release-notarize release-verify

release: release-sign release-notarize release-verify
	@echo
	@echo "$(ZIP) is signed, notarised and stapled."

# Hardened runtime and a secure timestamp: notarisation refuses a build
# without either. No entitlements file, because this app needs none -- it
# is not sandboxed, and outgoing network and its own keychain items are
# allowed under the hardened runtime as they are.
release-sign:
	@test -n "$(DEVELOPER_ID)" || { \
		echo "No \"Developer ID Application\" certificate in the keychain."; \
		echo "See the notes above the release target in the Makefile."; \
		exit 1; \
	}
	@swift build -c release
	@Scripts/assemble-bundle.sh "$(RELEASE_APP)" ".build/release/GitHubMonitor" "$(BUNDLE_ID)" \
		--sign $(DEVELOPER_ID) --options runtime --timestamp
	@echo "signed $(RELEASE_APP) with Developer ID"

# ditto rather than zip: the bundle carries symlinks and extended
# attributes that a plain zip drops, and a bundle that arrives at Apple
# missing them fails notarisation for reasons the log does not make
# obvious.
release-notarize:
	@/usr/bin/ditto -c -k --keepParent "$(RELEASE_APP)" "$(ZIP)"
	@xcrun notarytool submit "$(ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@xcrun stapler staple "$(RELEASE_APP)"
	@rm -f "$(ZIP)"
	@/usr/bin/ditto -c -k --keepParent "$(RELEASE_APP)" "$(ZIP)"

# What another Mac will conclude, asked here rather than found out by the
# first person to download it. `spctl` is Gatekeeper's own verdict and
# includes the notarisation ticket; `stapler validate` proves the ticket
# travels with the file rather than needing the network.
release-verify:
	@codesign --verify --strict --verbose=2 "$(RELEASE_APP)"
	@xcrun stapler validate "$(RELEASE_APP)"
	@spctl --assess --type execute --verbose=4 "$(RELEASE_APP)"

# Install into /Applications. Worth doing before enabling "launch at login":
# the login item records the app's path, so an app living in .build/ loses its
# entry on the next clean.
INSTALLED := /Applications/GitHubMonitor.app

# rsync rather than rm+cp: replacing the bundle wholesale gives it a fresh
# identity, and the keychain then asks for authorisation again on every
# install. Updating in place keeps the entry the user already allowed.
install: bundle
	@pkill -x GitHubMonitor 2>/dev/null || true
	@mkdir -p "$(INSTALLED)"
	@rsync -a --delete "$(APP)/" "$(INSTALLED)/"
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
