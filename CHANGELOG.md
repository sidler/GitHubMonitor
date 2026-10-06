# Changelog

What changed in each released version. The app shows this file itself, under
*GitHub Monitor → What's New*.

## Unreleased

- **The review's comments are in the diff.** Each conversation sits under
  the line it was written about, in either layout, with who said it and
  when. Resolved threads arrive folded to a line saying how many comments
  they hold — enough to see that something was discussed there without
  having to read it again. Fetched when the diff is opened rather than with
  the file list: the query carries every comment body, and arrowing down a
  list of pull requests should not pay for the discussion on each of them.
- The file list beside the diff says how many conversations each file
  still has open, and a shut folder sums up what is inside it. Counted by
  conversation rather than by comment: five replies arguing one point are
  one thing to deal with, and a list saying "5" would send somebody looking
  for five of them. The tooltip gives both numbers.
- Comments GitHub can no longer place — the code they were written against
  has since been rewritten — are gathered at the top of their file instead
  of guessed at a line. A remark about code that has changed is often still
  the remark that mattered.
- Code spans in any rendered body — descriptions, issue comments, review
  comments — now have a band behind them. Review comments are mostly about
  named things, and `use the id, not the login` read as a sentence with two
  odd nouns in it.
- **The words that changed are marked.** On a line that was edited rather
  than replaced, the parts that actually differ are drawn bold and on a
  stronger band, so a renamed identifier is one glance rather than two
  lines read character by character. Word by word, not character by
  character: marking the `s` in `getUser` becoming `getUsers` is precise
  and useless. A change in indentation alone is marked too — reformatting
  should be visible.
- **Side by side lines up what belongs together.** A removal and the
  addition answering it share a row only where the two are recognisably
  the same line; the rest get a row each, with a blank opposite. Before,
  the first removal was paired with the first addition whether or not they
  had anything to do with each other, which is only right when the two
  blocks are the same length and nothing moved — the case nobody needs
  help with.
- **Side by side.** The old file beside the new one, as well as the single
  column a patch comes in. Two columns are what you want where a line was
  edited rather than replaced: the word that changed sits opposite the word
  it changed from. A line with nothing answering it faces a tinted blank,
  because an empty cell beside an added line means "this did not exist",
  not "unchanged here". Switched from the diff's own header, from *View*,
  or in Settings, and remembered.
- Files in the diff are listed by path. The column and the file tree beside
  it now move together; the lists elsewhere still put the largest file
  first, which is the useful order in a pane four inches wide but not the
  order a diff is read in.

## 1.3.0

### Reading a diff

- The diff carries line numbers, each line's place in both files — before
  the change, then after. A removed line is numbered only in the old file
  and an added one only in the new, which is what tells you where a hunk
  actually lands. They can be switched off from *View → Show Line Numbers*
  or beside the text size in Settings, for the narrowest possible column.
- Ticking off the file you are reading now leaves the next one's first line
  at the top of the column. Folding takes height out of the page above
  where you are looking, so the scroll used to land somewhere in the middle
  of the following patch, with the lines above it gone and nothing saying
  they had been skipped. Ticking a file further down, or unfolding one,
  still leaves the page where it is.
### The menu bar

- A refresh GitHub does not answer leaves the last counts in the menu bar
  rather than replacing them with a warning triangle. A timeout is usually
  over before anybody looks, and counts that were right a minute ago are
  worth more than a symbol saying so. The triangle is kept for the one case
  it is still true of: a failure with nothing behind it, where the only
  alternative would be zeros that read as an empty queue. What went wrong
  is still said in red at the foot of the window and the popover, and now
  in the menu bar's tooltip too.

## 1.2.0

### Reading a diff

- The diff's text size can be chosen, from *View → Larger Diff Text* with
  ⌘+ and ⌘− while a diff is open, or from a stepper in Settings. Eight
  to twenty points. The patch only: the file names above it and the tree
  beside it are chrome, and a reader who wants the code bigger does not
  want the furniture bigger with it.
- The file's name stays at the top of the column while you read its patch,
  and the next file's name pushes it off. A long patch used to leave you
  scrolling through code with nothing saying which file it belonged to.

### Elsewhere

- This changelog, and the window under *GitHub Monitor → What's New* that
  shows it.
- A list item wrapped over several lines is one item again. Its tail used
  to fall out of the list and land at the margin as a paragraph of its
  own — in every pull request description, not only here.

## 1.1.0

### Viewed files, synchronised with GitHub

The diff overlay shows which files you have ticked off in GitHub's review
UI, and setting a tick here sets it there.

- Three states, not two. GitHub's *dismissed* — the file changed after you
  ticked it — is kept apart from *not viewed* and stays unfolded, because it
  is the file most worth reading again.
- A ticked file folds away, keeping its header and its place in the scroll.
- The header counts `n of m viewed`, and the file tree carries the same
  marks, so the list you jump with also says what is left.
- Nothing is ticked automatically as you scroll.

### The diff reads better

- Every file's patch opens in one scrolling overlay with a file tree to jump
  by, rather than unfolding inside a pane four inches wide.
- Patches are syntax-highlighted.

### Linked issues and pull requests

- What GitHub itself links, plus numbers written at the head of a title or
  in a description, told apart as *closes* and *mentioned*.
- One panel answers "what was this issue again" from the lists, from both
  detail panes and from the diff, so the diff need not be left.

### Lists

- Relative dates in a search — `closed:>@today-1w` and the like — are
  resolved before the search is sent. GitHub's web interface understands
  them; its search API does not, and answers that they are not a date.
- One list GitHub refuses no longer stops the others from refreshing. The
  list that was refused says what GitHub said, and is marked in the sidebar.
- Sorting, grouping and draft visibility are remembered per list.
- Lists can be written to a file and read back.

### Pull request detail

- The description renders as Markdown, folded away by default so the branch,
  the files and the checks keep their place. Tables, task lists, quotes and
  code fences included.
- Whether the pull request still merges into its base branch, in the row and
  in the pane.
- Approving from the diff, bound to the commit whose diff was on screen: if
  somebody pushed since you started reading, it is refused rather than
  applied to code you did not see.

### Elsewhere

- Settings report what GitHub actually charged for the last refresh, read
  from GitHub's own figure rather than estimated.
- Tooltips appear after 300 ms instead of a second and a half.
- The About panel says what the app is and links to its source.

## 0.1.0

The first signed and notarised build: lists you define, unread mentions,
the menu bar counts, the detail pane, and the workload and trend charts.
