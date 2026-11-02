# Changelog

What changed in each released version. The app shows this file itself, under
*GitHub Monitor → What's New*.

## Unreleased

- **A diff opens in its own window** instead of as a card over the app,
  so the code runs to the edges and the lists behind it stay usable.

- **Your own unsent remarks are marked in the file tree**, in the same
  purple they wear in the diff, so you can find your way back to what you
  have written but not sent.

- **Label a remark with the word that says what it is** — *issue*,
  *suggestion*, *praise* and nine more above the writing box, with
  *blocking*, *non-blocking* and *if-minor* beside them.
- **A shut conversation shows what it was about**, beside the count, so
  two settled threads no longer read as the same line.
- **The file tree marks the files that hold remarks**, not every folder
  above them.
- **A badge in a comment is drawn as a badge** instead of coming apart
  into two lines of markup.

## 2.3.1

- **A pull request's conversation is shown, not just counted** — the
  remarks nobody hung on a line of the diff, which is where the argument
  usually is.
- **A long remark wraps instead of being cut off** at the right of the
  column.
- **Settling a conversation folds it there and then**, rather than at the
  next opening.
- **Typing `@` offers a readable list** — opaque, and no longer painted
  over by the diff behind it.
- **The caret is in the box when it opens**, so writing a remark is one
  click rather than two.
- **Escape closes the box you are typing in**, not the whole diff with
  your half-written remark in it.
- **Prose inside a comment stays prose** — words like *and* or *return*
  in a docblock are no longer coloured as code.
- **A diff with conversations on it scrolls as smoothly as one without.**
- **The diff's header fits on one line** at any window width.
- **The folded line is blue**, so it no longer disappears among the grey
  comments in the code.

## 2.3.0

- **A pull request's commits, newest first**, each with its own checks —
  so you can see what arrived since you last looked, and when it went
  green. Fetched on the first click, not before.
- **An issue's type and milestone stop pretending to be labels** — only
  the labels open the label picker.
- **Taking a label off shows on screen**, instead of leaving the chip
  where it was while GitHub went ahead and removed it.

## 2.2.0

- **Open the list you are looking at on github.com**, from a button in
  the bottom bar — built from the search the app actually sent, filters
  and ordering included.
- **⌘R reloads the page you are looking at**, rather than always the
  lists. Reported by @marcreichel in #1.

## 2.1.0

- **The box you write a remark in looks like a box**, with *Add* and
  *Cancel* under the left edge where your hand already is.
- **The names an `@` offers float at the caret and the keyboard drives
  them** — ↑ ↓ to choose, ⏎ to insert, esc to dismiss. Nothing shifts
  while you type.
- **A conversation takes up less room**, about a line of code per thread.
- **Settled conversations stand in the diff, shut**, and open on a click.

## 2.0.0

- **Write remarks on the lines of a diff and send them as one review.**
  The line number turns into a plus; what you write joins a draft that is
  kept on disk until you send it, so one reading of a diff is one
  notification. Approve, ask for changes, or say the remarks without a
  verdict — and if somebody has pushed since you wrote them, it refuses
  rather than attaching your words to code you never read.
- **Reply to a conversation, and settle it**, in either layout.
- **Merge a pull request from the pane**, by whichever method the
  repository allows. It says what is in the way instead of going grey,
  asks before it acts, and merges the commit it showed you.
- **Read a diff one file at a time** — ‹ 3 of 6 ›, or ⌥← and ⌥→.
- **Typing `@` in a comment offers the people it can reach**, with the
  login and the real name beside it.
- **Set and clear labels from the pane**, on issues and pull requests
  both. The ones already carried come first in the picker.
- **A pull request shows the labels it carries.** It never did.
- **Pictures in a body are pictures** — screenshots and badges both,
  however they were written, with the full size one click away.
- **A conversation about code that has since changed stands where it was
  written**, and brings the few lines it was about with it.
- **Settled conversations are out of the way until you ask for them**,
  counted in each file's header.

## 1.8.1

- **The list column is drawn where it stands**, instead of sliding right
  and under the detail pane with every resize.
- **Widening the detail pane no longer shoves the sidebar** back to its
  minimum.

## 1.8.0

- **Settings has a Requests tab** — every call to GitHub, what came back,
  how long it took and what the hourly allowance had left, with a button
  that copies the lot.
- **The first rows appear as soon as they land**, rather than after every
  list has finished.
- **A momentary gateway error no longer empties the lists** for half an
  hour; it is asked again before it is believed.
- **The detail pane can be dragged as wide as there is room for.**
- **The files in the pull request pane are in the order the diff reads
  them in.**
- **⌘Q puts the window away rather than ending the app** — quitting is
  ⌘⌥Q, and still in the menu bar's popover.

## 1.7.0

- **Everything the app draws can be read on what it draws it on.** Every
  colour was walked along its own brightness until it clears 4.5 to one
  against every ground it actually appears on, in both themes, and a test
  keeps it there.
- **The detail pane counts the remarks on the diff**, which on a reviewed
  pull request is what you wanted to know. It said "0 comments" over
  forty of them.
- **A mention leads the pane it arrives in**, under its own heading,
  instead of sitting among twenty comments.
- **The mentions list says what was said**, not just which thread it was
  said in.
- **A file in the detail pane looks like something to press**, and a
  *Review* button opens the diff without picking a file first.
- **A pull request template's notes to the author are hidden**, as GitHub
  hides them.

## 1.6.1

- **The conversation count beside a file matches what the diff shows**,
  and every conversation the list counts is drawn somewhere.
- **A linked number is visible on the row you have selected** rather than
  white on white.

## 1.6.0

- **Opening a comment in the diff no longer moves the page** out from
  under the line you were reading.
- **The diff can be scrolled within a file**, and a large one scrolls at
  a quarter of the cost. It also fills the window.
- **A linked pull request's number says how it is going** — green for
  open, purple for merged, grey for closed.
- **Twelve more languages are highlighted**, variables and calls are
  marked as what they are, JSON reads as names and values, and PHP
  attributes stop being read as comments.
- **An issue's number is always visible, and one click copies it.**
- **The panel of linked issues can be resized, and stays that size.**
- **Signing out stops everything still in the air**, so the next account
  never sees the last one's data.
- **The pane's reload button fetches the ticks and review comments
  again**, which is also the answer to a force-push.
- **A list cut short is no longer reported as complete.**
- **Checks that share a name are told apart** — a failing leg of a matrix
  job could draw as a pass.
- **An approval you have just made stays on the row.**
- **A refresh asked for after a settings change actually asks.**
- **A review request with an unreadable timestamp no longer looks new**
  at every refresh.
- **`---` in a diff is a line of code**, not a file header, so a file
  whose only removal looked like one is drawn properly.

## 1.5.0

- **Long lines wrap instead of scrolling sideways**, in both layouts, and
  the two columns can no longer drift apart.
- **Side by side splits the width down the middle**, so every file opens
  looking the same.
- **The file list beside the diff can be dragged wider**, stays where it
  was put, and indents by four points a level rather than twenty-two.
- **Types have a colour of their own**, and far more words are painted
  than before.
- **A file that only adds or only removes lines is drawn across the whole
  width.**
- **The `+` and `−` markers sit in a column of their own**, so a wrapped
  line cannot be mistaken for a new one.

## 1.4.0

- **Each conversation sits under the line it was written about**, in
  either layout, with who said it and when. Settled ones arrive folded.
- **The file list says how many conversations each file still has open.**
- **Side by side** — the old file beside the new one, with a removal and
  the addition answering it on the same row where the two are
  recognisably the same line.
- **The words that changed are marked** on a line that was edited rather
  than replaced, word by word.
- **Code spans in a rendered body have a band behind them.**
- **Files in the diff are listed by path**, the same order the diff reads
  them in.

## 1.3.0

- **The diff carries line numbers**, each line's place in both files, and
  they can be switched off.
- **Ticking off a file leaves the next one's first line at the top of the
  column.**
- **A refresh GitHub does not answer leaves the last counts in the menu
  bar** rather than replacing them with a warning triangle.

## 1.2.0

- **The diff's text size can be chosen**, with ⌘+ and ⌘− while a diff is
  open.
- **The file's name stays at the top of the column** while you read its
  patch.
- **This changelog, and the window that shows it**, under *GitHub Monitor
  → What's New*.
- **A list item wrapped over several lines is one item again.**

## 1.1.0

- **Viewed files, synchronised with GitHub** — ticking a file here ticks
  it there, a ticked file folds away, and GitHub's *dismissed* stays
  unfolded because it is the one most worth reading again.
- **Every file's patch opens in one scrolling overlay with a file tree to
  jump by**, instead of unfolding inside a pane four inches wide.
- **Patches are syntax-highlighted.**
- **Linked issues and pull requests**, told apart as *closes* and
  *mentioned*, in one panel reachable from the lists, both detail panes
  and the diff.
- **Approving from the diff is bound to the commit you read** — if
  somebody pushed since, it is refused.
- **A pull request's description renders as Markdown**, folded away by
  default, and the row says whether it still merges into its base branch.
- **Relative dates in a search** — `closed:>@today-1w` and the like.
- **One list GitHub refuses no longer stops the others from refreshing.**
- **Sorting, grouping and draft visibility are remembered per list**, and
  lists can be written to a file and read back.

## 0.1.0

The first signed and notarised build: lists you define, unread mentions,
the menu bar counts, the detail pane, and the workload and trend charts.
