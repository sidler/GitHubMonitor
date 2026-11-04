# Changelog

What changed in each released version. The app shows this file itself, under
*GitHub Monitor → What's New*.

## Unreleased

- **Closing a review asks about remarks written but not added**, and
  keeps them as unsent remarks if that is what you want.
- **Several remarks can be half-written at once**, each on its own line,
  and they survive turning to another file: a box stays where it was
  opened, with what you typed still in it, and is there again when you
  come back.

## 2.5.0

- **Remarks can be formatted without typing markdown.** Buttons above the
  box for bold, italic, code, links, quotes and lists, with ⌘B, ⌘I,
  ⌘E and ⌘K, and a preview of what will be sent.
- **Backticks and accents can be typed in a remark again.** A key that
  waits for the next one — which on a German keyboard is how a backtick
  is typed — was being dropped before it became a character.
- **Large diffs open and scroll faster**, with files of a few thousand
  lines no longer juddering.
- **A diff of many files scrolls without stalling.** What each file needs
  is worked out while you read the first one, starting with the file you
  opened.
- **A pull request that has been pushed to is fetched again**, so the
  diff shows the same commit as the list of commits beside it.
- **An open diff says when the pull request has moved on**, with a button
  to fetch it again.

## 2.4.0

- **The token's description in Settings lists everything the app writes**
  with it: remarks and replies, reviews, resolving conversations, labels,
  viewed ticks and merges.

- **Reviews open in their own window**, with the code running to the
  edges.
- **Several reviews at once, as tabs.** A tab shows a dot while it holds
  remarks you have not sent.
- **The pull request's details beside the diff**, on ⌥⌘I: description,
  conversation, commits, checks, reviewers and the merge button. The edge
  can be dragged, and the width is remembered.
- **The code around a hunk, fetched from GitHub.** A row between the
  hunks says how many lines are hidden and brings them in on a press. The
  file header has a button for the whole file.
- **Conventional comment labels above the writing box** — *issue*,
  *suggestion*, *praise* and nine more, with *blocking*, *non-blocking*
  and *if-minor*.
- **A shut conversation shows its opening remark** beside the count.
- **The file tree marks the files that hold remarks**, and your own
  unsent remarks in purple.
- **Badges in comments are drawn as badges.**
- **Files with Windows line endings keep the usual line height.**
- **The tab bar leaves the list's title visible.**

## 2.3.1

- **A pull request's conversation**, under the description: the remarks
  that are not about a line of the diff.
- **Long remarks wrap** to the width of the column.
- **Settling a conversation folds it at once.**
- **Typing `@` offers an opaque list of names.**
- **The caret is in the box when it opens.**
- **Escape closes the box you are typing in.**
- **Prose inside a comment stays prose**, with no syntax colouring.
- **A diff with conversations on it scrolls smoothly.**
- **The diff's header fits on one line** at any window width.
- **The folded line is blue**, apart from the grey of code comments.

## 2.3.0

- **A pull request's commits, newest first**, each with its own checks.
  Fetched on the first click.
- **An issue's type and milestone are shown as what they are**; only the
  labels open the label picker.
- **Taking a label off shows on screen at once.**

## 2.2.0

- **Open the list you are looking at on github.com**, from a button in
  the bottom bar, with the filters and ordering carried across.
- **⌘R reloads the page you are looking at.** Reported by @marcreichel in
  #1.

## 2.1.0

- **The box you write a remark in has a border and a background**, with
  *Add* and *Cancel* under its left edge.
- **The names an `@` offers float at the caret**, driven by ↑ ↓ to
  choose, ⏎ to insert and esc to dismiss.
- **A conversation takes about a line of code less room.**
- **Settled conversations stand in the diff, shut**, and open on a click.

## 2.0.0

- **Write remarks on the lines of a diff and send them as one review.**
  The line number turns into a plus; what you write is kept on disk until
  you send it. Approve, ask for changes, or send the remarks without a
  verdict. If somebody has pushed since you wrote them, sending is
  refused.
- **Reply to a conversation, and settle it**, in either layout.
- **Merge a pull request from the pane**, by whichever method the
  repository allows. It says what is in the way, asks before it acts, and
  merges the commit it showed you.
- **Read a diff one file at a time** — ‹ 3 of 6 ›, or ⌥← and ⌥→.
- **Typing `@` in a comment offers the people it can reach**, with the
  login and the real name beside it.
- **Set and clear labels from the pane**, on issues and pull requests
  both. The ones already carried come first in the picker.
- **A pull request shows the labels it carries.**
- **Pictures in a body are drawn**, screenshots and badges both, with the
  full size one click away.
- **A conversation about code that has since changed stands where it was
  written**, with the few lines it was about.
- **Settled conversations are out of the way until you ask for them**,
  counted in each file's header.

## 1.8.1

- **The list column is drawn where it stands**, at every window size.
- **The detail pane can be widened without moving the sidebar.**

## 1.8.0

- **Settings has a Requests tab** — every call to GitHub, what came back,
  how long it took and what the hourly allowance had left, with a button
  that copies the lot.
- **The first rows appear as soon as they land.**
- **A momentary gateway error is asked again before it is believed.**
- **The detail pane can be dragged as wide as there is room for.**
- **The files in the pull request pane are in the order the diff reads
  them in.**
- **⌘Q puts the window away and leaves the app running**; quitting is
  ⌘⌥Q.

## 1.7.0

- **Everything the app draws clears 4.5 to one** against the ground it
  appears on, in both themes, with a test that keeps it there.
- **The detail pane counts the remarks on the diff.**
- **A mention leads the pane it arrives in**, under its own heading.
- **The mentions list says what was said.**
- **A file in the detail pane looks like something to press**, and a
  *Review* button opens the diff without picking a file first.
- **A pull request template's notes to the author are hidden**, as GitHub
  hides them.

## 1.6.1

- **The conversation count beside a file matches what the diff shows**,
  and every conversation the list counts is drawn somewhere.
- **A linked number is visible on the row you have selected.**

## 1.6.0

- **Opening a comment in the diff leaves the page where it is.**
- **The diff can be scrolled within a file**, fills the window, and a
  large one scrolls at a quarter of the cost.
- **A linked pull request's number says how it is going** — green for
  open, purple for merged, grey for closed.
- **Twelve more languages are highlighted**, variables and calls are
  marked as what they are, JSON reads as names and values, and PHP
  attributes are read as attributes.
- **An issue's number is always visible, and one click copies it.**
- **The panel of linked issues can be resized, and stays that size.**
- **Signing out stops everything still in the air.**
- **The pane's reload button fetches the ticks and review comments
  again**, which is also the answer to a force-push.
- **A list cut short says so.**
- **Checks that share a name are told apart.**
- **An approval you have just made stays on the row.**
- **A refresh asked for after a settings change is sent.**
- **A review request with an unreadable timestamp keeps its age.**
- **`---` in a diff is read as a line of code.**

## 1.5.0

- **Long lines wrap**, in both layouts, and the two columns stay level.
- **Side by side splits the width down the middle**, so every file opens
  looking the same.
- **The file list beside the diff can be dragged wider**, stays where it
  was put, and indents by four points a level.
- **Types have a colour of their own**, and far more words are painted.
- **A file that only adds or only removes lines is drawn across the whole
  width.**
- **The `+` and `−` markers sit in a column of their own.**

## 1.4.0

- **Each conversation sits under the line it was written about**, in
  either layout, with who said it and when. Settled ones arrive folded.
- **The file list says how many conversations each file still has open.**
- **Side by side** — the old file beside the new one, with a removal and
  the addition answering it on the same row where the two are
  recognisably the same line.
- **The words that changed are marked**, word by word.
- **Code spans in a rendered body have a band behind them.**
- **Files in the diff are listed by path.**

## 1.3.0

- **The diff carries line numbers**, each line's place in both files, and
  they can be switched off.
- **Ticking off a file leaves the next one's first line at the top of the
  column.**
- **A refresh GitHub does not answer leaves the last counts in the menu
  bar.**

## 1.2.0

- **The diff's text size can be chosen**, with ⌘+ and ⌘− while a diff is
  open.
- **The file's name stays at the top of the column** while you read its
  patch.
- **This changelog, and the window that shows it**, under *GitHub Monitor
  → What's New*.
- **A list item wrapped over several lines is one item.**

## 1.1.0

- **Viewed files, synchronised with GitHub** — ticking a file here ticks
  it there, a ticked file folds away, and GitHub's *dismissed* stays
  unfolded.
- **Every file's patch opens in one scrolling overlay with a file tree to
  jump by.**
- **Patches are syntax-highlighted.**
- **Linked issues and pull requests**, told apart as *closes* and
  *mentioned*, in one panel reachable from the lists, both detail panes
  and the diff.
- **Approving from the diff is bound to the commit you read**; if
  somebody pushed since, it is refused.
- **A pull request's description renders as Markdown**, folded away by
  default, and the row says whether it still merges into its base branch.
- **Relative dates in a search** — `closed:>@today-1w` and the like.
- **One list GitHub refuses leaves the others refreshing.**
- **Sorting, grouping and draft visibility are remembered per list**, and
  lists can be written to a file and read back.

## 0.1.0

The first signed and notarised build: lists you define, unread mentions,
the menu bar counts, the detail pane, and the workload and trend charts.
