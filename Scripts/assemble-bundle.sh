#!/bin/sh
# Assembles the .app bundle and signs it.
#
# Shared by the development build and the release build, which differ only
# in which identity signs and whether the hardened runtime is on. Keeping
# one copy means a change to the bundle's shape cannot reach one path and
# miss the other.
#
#   assemble-bundle.sh <output.app> <binary> <identifier> <sign-args...>
#
# With no sign-args the bundle is signed ad-hoc, which is not an identity:
# Little Snitch and the keychain treat every rebuild as a new application.
set -eu

app="$1"
binary="$2"
identifier="$3"
shift 3

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"

# The build number, written into the bundle rather than kept in the
# repository: it has to increase with every build an updater might compare,
# and the number of commits does that on its own without anybody having to
# remember. Falls back to the plist's placeholder outside a git checkout.
build=$(git rev-list --count HEAD 2>/dev/null || echo "")
if [ -n "$build" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$app/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp "$binary" "$app/Contents/MacOS/GitHubMonitor"

# Nothing is nested inside this bundle -- no frameworks, no XPC services,
# no helper tools -- so one signature covers it. Worth knowing before
# adding a dependency that brings its own: those must each be signed from
# the inside out, and `--deep` is not a substitute.
codesign --force --identifier "$identifier" "$@" "$app"
