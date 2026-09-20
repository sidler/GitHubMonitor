# GitHub Monitor

A small macOS menu bar app that shows how much GitHub work is waiting for you:

- **Reviews requested** — open pull requests where you (or one of your teams) are the requested reviewer
- **Unread mentions** — unread notification threads matching the reasons you care about

Both counts live in the menu bar. A popover gives a short overview, a separate
window gives the full lists, message previews and settings.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode not required — the Command Line Tools are enough)

## Build and run

```bash
make run
```

This compiles the package, assembles `.build/GitHubMonitor.app`, ad-hoc signs it
and launches it. Other targets:

| Target | Purpose |
|---|---|
| `make build` | Compile only |
| `make bundle` | Compile and assemble the signed `.app` |
| `make test` | Run the unit tests |
| `make clean` | Remove build artifacts |

The app has no Dock icon; look for its icon in the menu bar. `make run` kills a
previously running instance first.

To open a specific surface straight away — useful for screenshots, since the
app otherwise only reacts to a click on the status item — launch the binary
directly with `GHM_OPEN` set to `popover`, `pullRequests`, `mentions` or
`settings`:

```bash
GHM_OPEN=settings ./.build/GitHubMonitor.app/Contents/MacOS/GitHubMonitor
```

Note that `open` does not forward environment variables, so this needs the
binary path rather than `open -a`.

### Signing

Run this once before the first build:

```bash
./Scripts/create-signing-certificate.sh
```

It creates a self-signed code signing certificate in your keychain, and the
Makefile picks it up automatically.

If the script fails on the keychain import, use Apple's own route instead —
it does not go through PKCS#12 and is the more reliable of the two:

1. Open **Keychain Access**
2. Menu: *Keychain Access → Certificate Assistant → Create a Certificate…*
3. Name `GitHub Monitor Dev`, Identity Type *Self Signed Root*,
   Certificate Type **Code Signing**
4. Tick "Let me override defaults" and accept every following screen
5. Run `make bundle` — it finds the certificate on its own

Either way, `make bundle` prints which identity it used.

Without it the build falls back to an ad-hoc signature, which is *not* an
identity: Little Snitch reports "the process has no code signature" and asks
again after every build, and the Keychain treats each build as a different
application, so the stored token needs re-authorising every time. With the
certificate, both ask once and then remember.

### Network access

The app talks to `api.github.com` and `avatars.githubusercontent.com`. If you
run a firewall such as Little Snitch, allow those two hosts for GitHubMonitor.

## Setting up the token

The app needs a **classic** personal access token. Fine-grained tokens do not
reliably cover the notifications API.

1. Open <https://github.com/settings/tokens> → *Generate new token (classic)*
2. Give it a name such as `GitHub Monitor` and an expiry you are comfortable with
3. Tick these scopes:
   - `repo` — read pull requests, including private repositories
   - `notifications` — read notification threads and mark them read
   - `read:org` — list your team memberships so the app can offer them for selection
4. Copy the token and paste it into the app under *Settings → Account*

> **Note on `repo`:** this scope grants read **and write** access to all your
> repositories. The app only reads, but the token itself is more powerful than
> strictly necessary. This is a GitHub limitation of classic tokens — there is no
> read-only variant that still covers private repositories.

When the token expires, the menu bar icon switches to a warning symbol and the
popover tells you what to do.

## Configuration

| Setting | Effect |
|---|---|
| Menu bar display | Both counts / single total / hide zeros |
| Refresh interval | How often to poll. The app never polls faster than GitHub's own suggested interval, even when set to 1 minute. |
| Repository filter | Restrict counting to given owners or `owner/repo` entries |
| Include drafts | Whether draft pull requests count |
| Teams | Team review requests that should count as yours; loadable as a checklist from your memberships |
| Notification reasons | Which notification reasons count towards the mention badge |
| Launch at login | Register the app as a login item |

## Project layout

```
Sources/GitHubMonitorKit/   All logic and UI (unit testable)
  Model/                    Data models, settings, status bar title logic
  App/                      AppKit shell: status item, windows
  UI/                       SwiftUI views
Sources/GitHubMonitor/      Thin executable bootstrap
Tests/                      Unit tests for the non-UI logic
```
