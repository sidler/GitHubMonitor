# Changelog

What changed in each released version. The app shows this file itself, under
*GitHub Monitor → What's New*.

## Unreleased

- **A linked pull request's number says how it is going.** In the issue
  list the number was drawn the same whether the pull request answering
  the issue was still open or had been merged a week ago — which is the
  question being asked when the list is scanned. Green for open, purple
  for merged, grey for anything that is over without having been merged,
  and the tooltip spells it out. GitHub's own colours, because those are
  the ones anybody reading them already knows.
- It costs nothing: those nodes were already being fetched for their
  titles, so the state rides along in the same request. A number read out
  of prose still has no colour until it has been looked up, which is the
  honest answer — a chip drawn green because nobody said otherwise would
  be a lie about something merged last week.

- **Opening a comment in the diff no longer moves the page.** Unfolding a
  conversation scrolled the file out from under the line being read, and
  folding it again did the same — sometimes far enough to bring the
  previous file back into view. The scroll view was being handed back the
  file it had just reported, and that modifier does not merely report
  where you are: it *holds* what it is given, and re-applies the hold
  whenever the content changes size, which is exactly what opening a
  conversation does. Told to keep a file whose top was far above the
  window, it pulled the page back to it. Going somewhere and being
  somewhere are two things now. Clicking a file in the list still jumps to
  it, the list still marks the file being read, and ticking a file off
  still lands on the next one at its first line.

- **Variables are marked as variables.** PHP and the shell introduce every
  one with a `$`, which is exactly the word a reader follows down a diff,
  and it was painted like any other. `$this->total($row)` now says in
  three colours what it is made of: the variables, the call, and the
  brackets between them.
- **A name with a `(` after it is drawn as a call**, in every language
  that has them. A signature is a name, its types and its parameters, and
  only the types had a colour of their own.
- **Twelve more languages are known**: HTML and Twig as themselves rather
  than as XML, plus Python, Java, C#, C/C++, Go, Rust, Swift, Kotlin, Ruby,
  SQL and shell. A Swift or Go fence in a comment is highlighted now, and
  so is a `.sql` file in a diff.
- HTML and Twig draw their tags and their attribute names apart, and Twig's
  `{{ }}`, `{% %}` and `{# #}` are marked as the template's own. A
  Makefile and a Dockerfile are left plain, because each has a syntax of
  its own and painting them as shell would paint the wrong words.
- **JSON reads as names and values** rather than as a column of red: a
  quoted name before a colon is drawn as a name. The same in JavaScript
  and TypeScript object literals.
- `#[Attribute]` in PHP is an attribute, not a comment. `#` does open a
  comment there, so the whole declaration under one of these turned grey.
- Annotations and decorators — `@Override`, `@property`, `@Input` — are
  drawn as the names they are.

- **The panel of linked issues can be resized, and stays that size.** Drag
  the corner; double-click it to give the panel back to its contents. It
  was four hundred and twenty points wide with a height counted from how
  many cards it held, which is the wrong measure when one card holds a
  long summary — there was room for two lines of it and no way to ask for
  more. One size serves all three places the panel opens from, because it
  is one panel answering one question.
- The diff is no longer capped at eleven hundred points tall. It fills the
  window, which is what the comment above the cap always said it did.
- **An issue's number is always visible, and copying it is one click.**
  It shared one line with the repository, the author and the date, and
  that line is truncated from the end in a pane this narrow — so the
  number was the first thing to go. The repository gives way now, in the
  middle, and the number does not. Clicking it copies `#1234`. The pull
  request pane does the same, since the two sit side by side.

- **Signing out now stops what is in the air.** Stopping cancelled the
  refresh timer and the list request, and nothing else: the three charts
  and eleven per-item fetches carried on, each still holding the service
  of the account being left. A detail, a patch, a private issue's title
  or a year of trends asked for a moment before signing out landed a
  second afterwards and wrote itself back into the state that had just
  been cleared. Every one of them is now held so it can be called off,
  and none of them writes what it brings back once it has been. The
  review comments were missing from the clearing-out altogether, so the
  next account to sign in saw the previous one's discussion on the same
  pull request.
- **Reload fetches the ticks and the review comments again.** Both are
  claimed before their request goes out and left claimed when it fails,
  which is what stops a redraw asking again — but it also meant one
  failed request hid a pull request's conversations for the rest of the
  session, with nothing able to ask a second time. The pane's reload
  button is that second time. It is also the answer to a diff that has
  moved on: after a force-push, comments anchored to the old line
  numbers are worse than no comments. They are forgotten along with the
  pull request when it leaves the lists, rather than being kept for the
  life of the process.
- **A list cut short is no longer reported as complete.** A complaint
  from GitHub that names no list is about the request itself and nothing
  in the answer can be trusted — but the check asked whether *any* list
  had failed so far, so one list refused on the first page stood as the
  explanation for every complaint in every round after it. A
  request-level error while paging was swallowed, the loop ran dry, and
  the lists that still had pages to fetch were presented as whole. The
  question is now asked of each complaint on its own, which also catches
  a request-level error arriving alongside a list-level one.
- **`---` in a diff is a line of code, not a file header.** Four places
  decided whether a line had changed, and they disagreed. A removed SQL
  comment arrives as `--- note`, a removed Markdown rule as `---`, a
  removed `--i;` as `---i;` — and one of those four treated all of them
  as a patch's file headers, which GitHub does not even send. A file
  whose only removal looked like that was reported as one-sided and
  drawn in a single column, whatever layout you had chosen; and because
  the other three disagreed, one column and two columns paired different
  lines and marked different words in the same file. The rule is one
  rule in one place now, and it goes by position: a header can only
  stand before the first `@@`.
- **An approval you have just made stays on the row.** The guess written
  into the row while GitHub's search index catches up was being read
  back as GitHub's own confirmation, so it was dropped one step early
  and the next refresh put the lagging answer on screen — losing the
  approval, which is the one thing the guess exists to prevent.
- **A refresh asked for after a settings change actually asks.** A
  refresh fixes its searches when it starts, and a second call simply
  joined it — so switching a list on, adding a preset or changing a
  repository filter reported success without the new query ever having
  been sent, and the list filled in at the next tick instead of at once.
- **Checks sharing a name are told apart.** A matrix job names every leg
  the same, and the list keyed on the name: three legs of `phpunit` with
  one failure among them could draw as three passes while the heading
  above said one was failing.
- **A notification about a release no longer asks for an issue.** Any
  numeric subject URL was taken for a conversation, so a release earned
  a wasted request and an error where "no conversation to show" was the
  honest answer.
- **Reopening the window watches it scroll again.** Closing took the
  observer away and reopening did not put it back, so the band behind
  the title stayed as it was and rows scrolled through it.
- **A review request with an unreadable timestamp no longer looks new.**
  It was given the current time, which restarted the waiting clock at
  every refresh, so the row never aged. Timestamps carrying a fraction
  of a second are read properly now, and one that still cannot be read
  shows no clock rather than a wrong one.
- The ageing thresholds are clamped like every other number read from
  preferences. At zero every review that had started waiting was overdue
  at once, and the Settings pickers offered no row that could put it
  back.
- The trends fetch reads the lower of its two budget replies rather than
  whichever arrived first, so it stops where it is meant to.
- **A large diff is painted once, not on every frame.** Every visible
  line was re-scanned and re-coloured whenever the view rebuilt, and the
  tables of keywords and types were built again from scratch for every
  word looked up. A screenful of a large PHP diff cost five and a half
  milliseconds a frame; it now costs well under a tenth of that.
- The patch cache keeps what is being read rather than what arrived
  first. In a review of more than sixty-four files the file at the top
  of the column — read on every frame — was thrown out to make room for
  one being scrolled past.

## 1.5.0

- The diff fills the window. It was capped at 1500 points wide, which on a
  wide screen left most of the glass empty — and a wide screen is exactly
  where two columns of code have somewhere to go.
- **Side by side splits the width down the middle**, whatever is in the
  file. Columns sized to their own longest line put the divider somewhere
  different in every file, so a review was read down a page whose shape
  changed at every heading; now every file opens looking the same.
- **The file list beside the diff indents less.** It is drawn flat with
  an indent of its own rather than as nested groups, because a list that
  nests its own groups sets each level in by an amount it does not offer
  to change — and at six levels, which a Java or PHP module reaches
  without trying, that left a sliver for the file name with the rest of
  the row to the left of it. A level is four points now rather than
  twenty-two, and the rows are pulled back over the inset the list keeps
  at its own leading edge whatever it is told.
- The pencil beside a modified file is gone. Nearly every file in a review
  is modified, so it was a column of one repeated symbol, and in a list
  this narrow that column cost as much as two levels of indentation. Added,
  removed and renamed files keep their mark, which is where it says
  something.
- **Types have a colour of their own**, and far more words are painted
  than before. A signature is mostly types, and `public function
  matches(array $row): bool` in one purple says nothing; `array` and
  `bool` are teal now. PHP gained its `end*` forms, `isset`, `unset`,
  `require_once` and the rest; TypeScript gained `satisfies`, `keyof`,
  `infer`, `override` and its built-in types; CSS gained the at-rules and
  keywords it has grown since.
- A file that only adds lines, or only removes them, is drawn across the
  whole width even in the two-column layout. There is nothing to put on
  the other side, and half a window of blank facing the only column that
  says anything helps nobody.
- **The file list beside the diff can be dragged wider or narrower**, and
  stays where it was put. The edge is twelve points of grab centred on the
  line, and it shows itself under the pointer so there is something to aim
  at. Dragging moves a line and the diff reflows once when the hand comes
  off: every line wraps to its column, so changing that column on every
  frame of the drag would re-wrap the whole file sixty times a second,
  which is not resizing but flickering. How much width a path needs is a
  judgement about one person's repositories — deeply nested Java wants
  more of it than a flat Go project — and nobody wants to make that
  judgement twice.
- **Long lines wrap instead of scrolling sideways.** Nothing in the diff
  scrolls horizontally any more, in either layout. That is what finally
  made the two-column view simple: no scroll views inside a file, nothing
  to keep in step, and a row whose two halves share one height because
  they are one row — so a line that wraps on one side takes the other
  down with it and the columns cannot drift apart.
- The `+` and `−` markers sit in a column of their own. A wrapped line
  would otherwise carry on where a marker would be and read as a line of
  its own, which is the confusion a diff exists to prevent; in its own
  column the marker cannot be mistaken for anything, and what wraps lines
  up under the code it belongs to.
- **One file is one container.** The two-column diff was cut into a piece
  per hunk and a piece per comment, each piece a pair of scroll views kept
  level with the others by passing positions around. A review of forty
  files became hundreds of scroll views sending one another messages,
  which is what made scrolling such a review wobble and horizontal
  scrolling behave as though it had a mind of its own. Each column of each
  file is now one view holding every row of that column; nothing is kept
  in step because there is nothing to keep in step.
- The hunk header is split between the columns: the old file's range on
  the left, the new file's on the right, with the enclosing function on
  both. A line belonging to both files has nowhere to go in two columns —
  and no need, because each side has a half of its own.
- **The diff can be scrolled within a file at all.** The file at the top
  of the column was written back into the app's state on every frame,
  which rebuilt the overlay and handed its scroll view that position
  again — and SwiftUI took the handover for an instruction, pulling the
  file being read back to the top. You could step from file to file and
  barely move inside one. With the short files in a small review that
  passed for scrolling; on a real review of long files the page simply
  would not move. The overlay keeps its own place now.
- **A large diff scrolls at a quarter of the cost.** Nearly all of the
  layout time went into building one accessibility element per coloured
  token: a thousand lines of code made thousands of them, each walked
  again on every frame. One element per line now, carrying the line as its
  label, which is the useful unit anyway.

## 1.4.0

### The review's comments, in the diff

- **Each conversation sits under the line it was written about**, in
  either layout, with who said it and when. Resolved threads arrive folded
  to a line saying how many comments they hold — enough to see that
  something was discussed there without having to read it again. Fetched when the diff is opened rather than with
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

### Reading a diff

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
### Elsewhere

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
