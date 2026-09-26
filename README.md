# GitHub Monitor

A macOS menu bar app that shows how much GitHub work is waiting for you — and
lets you do most of the reviewing without leaving it.

The counts live in the menu bar. A popover gives a short overview; a separate
window gives the full lists, the diffs, the charts and the settings.

## What it does

**Lists you define.** Each is a title and one or more GitHub searches, shown as
pull requests or as issues. It starts with reviews requested of you or your
teams, the pull requests you opened, and the issues assigned to you — all three
editable like any other, and all of them exportable to a file and importable
again. A list's search is GitHub's own syntax, one search per line, results
merged. `@me` is you, and GitHub resolves team membership itself. Lists page to
300 rows and say how many more the search found.

**Unread mentions.** Unread notification threads matching the reasons you care
about. Not a search, so not a list: they come from the notifications API, which
has an hourly allowance of its own.

**Rows that answer at a glance.** Review decision, check results, whether the
pull request still merges into its base branch, how far the review has got, and
how long it has been waiting on *you* — the date turns orange and then red once
your own review has been outstanding too long. Every symbol has a tooltip,
which appears after 300 ms rather than the system's second and a half.

**Sorting and grouping per list.** Last updated, date opened, type, or waiting
longest; flat, by repository, or by type. Drafts shown or hidden. Each list
remembers its own choices.

**A detail pane** for the selected row: branch and merge state, the change
counts, the description rendered as Markdown — folded away by default, so the
rest is not pushed off the pane — every changed file, every check with its
result, and each reviewer with where they stand. Markdown includes tables,
task lists, code fences with syntax highlighting, and quotes.

**The diff, over the window.** Clicking a file opens every file's patch in one
scrolling overlay with a file tree to jump by, because a diff read three words
at a time in a 400-point pane is not read.

**Approving, from the diff.** The approval is bound to the commit whose diff was
on screen: if somebody pushed since you started reading, it is refused rather
than applied to code you did not see. It asks first, says whether auto-merge is
armed, and the list and pane carry the approval straight away. "Request
changes" opens the pull request on GitHub, where a review can be written
against the lines.

**Linked issues and pull requests.** What GitHub itself links, plus numbers
written at the head of a title or in a description. A panel — the same one from
the list, from both detail panes and from the diff — summarises the other side
without leaving what you were reading.

**Charts.** *Workload* is one repository's open pull requests per author, ready
and draft as separate segments. *Trends* follows a repository over time. *My
Trends* is about you: how long reviews wait on you, how fast you answer, and
who you review with.

**The hourly budget, in plain sight.** Settings report what GitHub actually
charged for the last refresh and what that comes to over an hour, read from
GitHub's own figure rather than estimated. Refreshing stops on its own when the
allowance runs low and picks up again when it is restored.

## Requirements

- macOS 26 or later — the app uses the system's own glass materials rather than
  reproducing them
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
| `make install` | Copy the app to `/Applications` and launch it |
| `make uninstall` | Remove it from `/Applications` |
| `make icon` | Regenerate `AppIcon.icns` from `Resources/AppIcon.svg` |
| `make test` | Run the unit tests |
| `make clean` | Remove build artifacts |

Install before enabling *launch at login*: the login item records the app's
path, so an app running from `.build/` loses its entry on the next clean. If
the setting was already on, switch it off and on again after installing.

The app has no Dock icon; look for its icon in the menu bar. `make run` kills a
previously running instance first.

To open a specific surface straight away — useful for screenshots, since the
app otherwise only reacts to a click on the status item — pass `--open` with
`popover`, `mentions`, `dashboard`, `trends`, `myTrends`, `settings` or a
list's id. `--sample` fills the app with made-up data so the whole interface
can be exercised without a token.

```bash
open -n /Applications/GitHubMonitor.app --args --open settings --sample
```

`settings:general` opens a particular settings tab. The same switches are read
from the environment as `GHM_OPEN` and `GHM_SAMPLE`, which is what to use when
launching the binary directly rather than through `open`.

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

Settings are split into four tabs.

**Account** — the token, and the teams whose review requests count as yours
(loadable as a checklist from your memberships).

**Lists** — the lists themselves: title, symbol, searches, what they show, and
where each appears (window, popover, menu bar). Drag to reorder; the sidebar,
the popover and the menu bar all follow that order. Lists can be written to a
file and read back, with a confirmation naming what an import would replace.

**Filters**

| Setting | Effect |
|---|---|
| Repositories | Restrict counting to given owners or `owner/repo` entries. "Add from current results" offers what is actually in your lists. |
| Mention reasons | Which notification reasons count towards the badge. With none selected the count stays at zero. |

**General**

| Setting | Effect |
|---|---|
| Menu bar display | All counts / single total / hide zeros |
| Waiting reviews | After how many days a waiting review is marked, and when it is called overdue |
| Sidebar | Whether to hide the repository row when a list covers only one |
| Refresh interval | How often to poll, with what the last refresh cost |
| GitHub's hourly budget | What is left of each allowance, and when it resets |
| Launch at login | Register the app as a login item. The entry points at the app's current location, so moving it afterwards breaks it. |

While the main window is open the app behaves as an ordinary application: it
appears in the Dock and the app switcher and shows a menu bar with the usual
shortcuts (Cmd+, for settings, Cmd+R to refresh, Cmd+W to close, and
Cmd+Option+arrows to move the detail pane down the list). Closing the window
returns it to a menu bar agent with no Dock icon.

## Project layout

```
Sources/GitHubMonitorKit/   All logic and UI (unit testable)
  Model/                    Data models, settings, status bar title logic
  App/                      AppKit shell: status item, windows
  UI/                       SwiftUI views
Sources/GitHubMonitor/      Thin executable bootstrap
Tests/                      Unit tests for the non-UI logic
```
