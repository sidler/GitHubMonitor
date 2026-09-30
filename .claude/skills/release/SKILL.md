---
name: release
description: "Cut a release of GitHub Monitor: version the bundle, move the changelog, sign and notarise with a Developer ID, publish the GitHub release and update the Homebrew cask. Use when asked to release, ship, publish or tag a version of this app, or to update the brew cask after one. Not for ordinary builds — `make bundle` and `make install` need none of this."
---

## What a release is here

Five things have to end up agreeing with each other, and a release is
finished only when all five do:

| | |
|---|---|
| `Resources/Info.plist` | `CFBundleShortVersionString` |
| `CHANGELOG.md` | a `## <version>` section, newest first |
| the git tag | `v<version>` |
| the GitHub release | `GitHub Monitor <version>`, with the zip attached |
| the cask | `version` and `sha256` in `sidler/homebrew-tap` |

Anything less is a half-release somebody discovers later: a tag with no
download, or a cask pointing at a file that is not there.

## Before starting

Ask the user for the version number if they did not say one, and ask
whether the entries under *Unreleased* are what they want to ship. Do not
pick a version yourself — the difference between 1.1.1 and 1.2.0 is a
judgement about the work, not about the diff.

Three things must already be true, and none can be arranged from here:

1. A **Developer ID Application** certificate in the keychain
   (`security find-identity -v -p codesigning | grep "Developer ID"`).
2. Notarisation credentials stored under the profile `GitHubMonitor`.
   These are the user's Apple credentials: **never type them into a
   command.** If the profile is missing, stop and give the user the
   `xcrun notarytool store-credentials` line to run themselves.
3. **The machine unlocked, with the display awake.** Signing reaches into
   the keychain, and so does the commit signature. A sleeping display
   fails both with errors that name neither cause: `1Password: failed to
   fill whole buffer` on the commit, and a codesign that hangs. Wait for
   the user rather than reaching for `--no-gpg-sign`.

## The steps

### 1. Version the bundle

Set `CFBundleShortVersionString` in `Resources/Info.plist`.

Leave `CFBundleVersion` alone. `Scripts/assemble-bundle.sh` overwrites it
at build time with `git rev-list --count HEAD`, so it rises on its own and
a hand-edited value is thrown away. It does mean **the build must be made
after the version commit**, or the number belongs to the previous state.

### 2. Move the changelog

Rename the `## Unreleased` heading to `## <version>`, keeping it above the
older versions. Add a new empty *Unreleased* section only once there is
something to put in it.

Two things depend on the shape of that file, both of which break quietly:

- `Changelog.newestVersion(in:)` returns the first `## ` heading **that
  begins with a digit**. A version heading that starts with anything else
  is skipped, and the "What's New" window falls back to its plain title.
- `ChangelogTests` names the shipped versions literally
  (`#expect(text.contains("## 1.1.0"))` and the expected newest version).
  **Update that test in the same commit** — it is the one test that has to
  be edited every release, and it is meant to be: it is what stops a
  release going out with a changelog nobody moved.

### 3. Test

```bash
make test
```

`swift test` on its own fails here — without a full Xcode the swift-testing
macro plugin sits where SwiftPM does not look, and `make test` passes the
plugin path. A failure that says `external macro implementation type ...
could not be found` is that, not a broken test.

### 4. Commit and tag

Commit the version, the changelog and the test together. Then tag:

```bash
git tag -a v<version> -m "GitHub Monitor <version>"
git push && git push --tags
```

### 5. Sign and notarise

```bash
make release
```

This builds in release configuration, signs with the Developer ID under a
hardened runtime and a secure timestamp, submits the zip to Apple, waits,
staples the ticket and then asks Gatekeeper what another Mac would
conclude. It takes a few minutes, nearly all of it Apple's queue.

It leaves `.build/release-app/GitHubMonitor-<version>.zip`.

Read the output rather than the exit code: `notarytool` prints
`status: Accepted`, and `spctl` prints `source=Notarized Developer ID`.
If notarisation is rejected, `xcrun notarytool log <submission-id>
--keychain-profile GitHubMonitor` says why — usually a missing hardened
runtime or timestamp on something added to the bundle since.

### 6. Publish the GitHub release

```bash
gh release create v<version> \
  .build/release-app/GitHubMonitor-<version>.zip \
  --repo sidler/GitHubMonitor \
  --title "GitHub Monitor <version>" \
  --notes-file <notes>
```

Write the notes from the changelog section, not from the commit log, and
end them with the install block and one line saying the build is signed,
notarised and stapled. Look at the previous release for the shape
(`gh release view v1.1.0 --repo sidler/GitHubMonitor --json body`).

### 7. Update the cask

The tap is `sidler/homebrew-tap`, checked out locally at
`/opt/homebrew/Library/Taps/sidler/homebrew-tap`, which is an ordinary git
clone — commit and push there.

Take the checksum from **the file GitHub serves**, not the local zip:

```bash
curl -sL https://github.com/sidler/GitHubMonitor/releases/download/v<version>/GitHubMonitor-<version>.zip | shasum -a 256
```

They should match, and it costs one `curl` to know rather than assume — a
wrong `sha256` in a cask fails on the user's machine, not on yours.

Then set `version` and `sha256` in `Casks/githubmonitor.rb`, commit as
`githubmonitor <version>` and push.

### 8. Check that it actually installs

```bash
brew update && brew info --cask githubmonitor
```

If you install it to be sure, note that a cask-installed bundle in
`/Applications` is protected: a later `make install` fails with `Operation
not permitted`. Run `brew uninstall --cask githubmonitor` before going back
to development builds.

### 9. Update the README if the install story changed

The README's *Releasing a signed, notarised build* section is the prose
version of this skill. If a step here changes, it changes there too.

## Reporting back

Say plainly which of the five things above are done and which are not, and
give the release URL. If notarisation or the cask push did not happen, say
so — a release that is 80% done and described as done is worse than one
that is 80% done and described as 80% done.

Never filter the output of a step through `grep` and then treat "no
output" as success. That is how a failed install once looked like a
successful one for twenty minutes. If you filter, check that something
came back.
