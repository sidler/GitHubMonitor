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

### Why the app is signed

The GitHub token is stored in the macOS Keychain, and Keychain access control is
tied to the app's code signature. The build ad-hoc signs the bundle with the
fixed identifier `com.sidler.githubmonitor` so the stored token stays reachable
across rebuilds. macOS may still ask for permission once after a rebuild —
choose "Always Allow".

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
