# Changelog

What changed in each released version. The app shows this file itself, under
*GitHub Monitor → What's New*.

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
