# Changelog

What changed in each released version. The app shows this file itself, under
*GitHub Monitor → What's New*.

## Unreleased

- **A pull request shows the labels it carries.** It never did: the lists
  ask for them on issues and pass an empty set for pull requests, so a
  team that sorts its work by label could see that everywhere but here.
  They are drawn in the pane and not in the row — a pull request row
  already carries its checks, its reviewers, its draft mark and the
  issues it closes, and the labels would be the line that broke it.

  Fetched when the item is opened rather than with the lists, so a
  refresh costs nothing more for them, and fifty of them rather than the
  row's ten: a pane that will shortly offer to change them cannot be
  looking at ten of twelve. An issue's pane now shows its full set for
  the same reason.
- **The settled conversations are out of the way until you ask for
  them.** A file's header in the diff says how many it is holding — “3
  resolved” — and the count is the control: one click shows them where
  they belong, another puts them back. Per file, and only while the diff
  is open, which is the same bargain the folders in the tree make. A
  review that went well is mostly settled conversations, and reading the
  diff afterwards meant reading around them; but they are also the record
  of why the code looks the way it does, so hiding them for good would
  throw away the answer along with the question.

  Settled means resolved, and nothing else. A remark about code that has
  since been rewritten but that nobody ever answered is still somebody's
  open question — it only looks like history, and it stays where it is.
- **A conversation about code that has since changed stands where it was
  written.** It used to be swept into a pile under the file's name, and
  since a remark is usually settled by changing the code — which is
  exactly what makes GitHub drop the line it was on — that pile was most
  of a finished review. Each one now sits at the line it was written
  against, and brings the few lines it was about with it: the code as it
  stood then, taken from what GitHub stored with the remark, with the
  commented line darker than its neighbours.

  Placed near rather than on, and the difference matters. The line a
  thread remembers counts in a version of the file the diff no longer
  carries, so no arithmetic turns it into a line that is really there —
  it lands after the last line at or before it. Carrying its own code is
  what makes that honest: nobody has to assume the remark was about
  whatever ended up next to it. Only a thread GitHub gives no number for
  in either version is still gathered at the file's header.
- **A conversation in the diff takes the room it needs and no more.** Each
  one sat in a rounded box with ten points of padding on four sides, a
  twelve-point inset on top of that, and eight between every reply — so a
  thread of four answers was taller than the hunk it was about. The box is
  gone. In its place a rule down the left edge, in the colour of what the
  thread is: blue while it is open, grey once it is resolved, orange for
  one written against code that has since been rewritten. Replies are told
  apart by a hairline instead of by distance.

  The quarter of dimming that resolved and outdated threads used to get
  has gone with it. It took a quarter off the text as well as the chrome,
  which is the one thing the contrast of this app is not allowed to be
  casual about — and with a grey rule and a line naming the state, it was
  saying a third time what had already been said twice.

## 1.8.1

- **The list column is drawn where it stands.** With the detail pane open
  it was rendered tens of points to the right of the column it belongs
  to: a white strip beside the sidebar, and the far end of the rows
  disappearing under the pane. Every resize pushed it further. The
  measurements were right the whole time — the column reported its true
  width and no inset — so the only thing visibly wrong was where the
  result was put. A `GeometryReader` wrapped around the whole column was
  doing it; it is only needed for the height of the title band, so it now
  sits inside that band's overlay, off the path the list is measured on.
- **Widening the detail pane no longer moves the sidebar.** Pulled past
  the point where the list column had no more room to give, the drag went
  straight through it and into the sidebar, which snapped back to its own
  minimum and cut off the names it had been widened to show. That is
  NSSplitView's own habit -- a divider dragged past what its neighbour can
  give pushes the divider behind it -- and the sidebar is not part of the
  conversation between those two columns. The drag now stops where the
  list reaches its minimum, and nowhere further.

  Where the drag stops is worked out from how narrow the list column can
  really be, which is not the number set on it: the counts along its
  bottom and the title above stop being able to give at a width of their
  own, and the forty points of difference were coming out of the sidebar.

  Which column gives way when the *window* changes size is now said out
  loud as well: the middle one. It takes what a wider window brings and
  gives up what the panes beside it need, which is what kept the sidebar
  and the detail pane at the widths they were set to.

## 1.8.0

- **A gateway error is asked again before it is believed.** GitHub ends
  any request that runs past ten seconds with a 502 or a 504, which is a
  statement about that moment rather than about the request — and the app
  took it as final. One of them at startup left every list empty until the
  next refresh, which is up to half an hour away. Now a read is sent again
  after a second, and once more after three, before the error stands.

  Only requests that change nothing: a 502 says the gateway got no answer,
  not that nothing happened behind it, and a second send of an approval is
  a second approval. Reads and queries are repeated, mutations and writes
  are not. Every attempt appears in the Requests tab, including the ones
  that were followed by another — a log showing only the answer that
  worked would say the gateway had been fine.
- **The first page of each list is smaller.** Every list asks for its
  first page in the same request, at the same moment, with nothing cached
  behind it, and each row carries its checks, its reviewers and its
  timeline. A hundred rows per list was what pushed that one request past
  GitHub's ten seconds. It asks for thirty now, which is already more than
  a window shows; the pages after it still ask for a hundred and still run
  to the same cap, and the counts beside a list come from GitHub's own
  total, which never cared how many rows were fetched.

  And the first page is now shown as soon as it lands, instead of the
  window staying empty until every list has finished paging. Only on the
  first load, while there is nothing there to disturb: on a later refresh
  the rows stay as they are until the whole answer is in, because a list
  that shrank to thirty and grew back would read as the refresh
  flickering rather than working.
- **The detail pane can be dragged as wide as there is room for.** It had
  a ceiling of four hundred points — a guess about how much anybody would
  want, which is not a thing to guess about. An inspector pane in AppKit
  is fixed at one width unless both ends are said out loud, so taking the
  ceiling away had left it pinned rather than free. The drag now stops
  where the list beside it needs the room, and nowhere earlier. Four
  hundred is still where it opens, and now also as narrow as it goes.
- **Settings has a Requests tab.** Every request to GitHub and what came
  back: when, which call, the status, how long it took, what the hourly
  allowance had left, and — where something went wrong — what GitHub
  actually said. A 502's body names the part of GitHub that failed, and
  that body was being thrown away with the error. The successes are kept
  as well, because a log holding only the failures cannot say whether
  anything was working in between, which is the first question about an
  intermittent one. There is a filter for the refusals alone and a button
  that copies the lot as text.

  All GraphQL calls post to the same path, so each is named by the field
  its query asks for — `graphql search`, `graphql repository` — which is
  enough to tell one from another and carries no values. The last few
  hundred, in memory only: nothing is written to disk.
- **The files in the pull request pane are in the order the diff reads
  them in.** They were sorted biggest first, on the reasoning that in a
  narrow pane the useful question is where the work is — but that list is
  a way into the diff, each row opens it at that file, and the tree
  beside the diff is in path order. The two disagreed about what came
  after what. A list you navigate by has to match the thing it navigates.
- A file in the pull request pane takes a quiet ground under the pointer,
  alongside the chevron that was already there.
- The three numbers a row reports about its reviewers — approvals,
  objections, awaited — were the last palette still on the system's own
  colours, and the green was light enough to show it. Five palettes, and
  the sweep that fixed four read past the file holding the fifth.
- **The last of the colours that were still the system's own.** The
  checks and the reviewers in the pull request pane kept a second copy of
  the palette, written out beside the view that used it, and it had
  drifted: a green tick there stayed on the system's green at 2.2 to one
  while the same tick in a row had already been weighted. That copy is
  gone, and so are thirty other places that reached for `.green`, `.red`
  or `.orange` directly — a warning triangle, a rate-limit figure, the
  `+5 −2` beside a file, the tick that says a number was copied. The
  colours a review state is drawn in now live beside the legend that
  explains them, like every other palette.

  The bands behind a diff's changed lines and the colours of a chart's
  series are left as they are: one is the ground the palette was measured
  against, the other is read by comparing one line with another rather
  than against the page.
- **Cmd+Q puts the window away rather than ending the app.** This one
  lives in the menu bar, where its job is to keep watching after you have
  finished looking — and Cmd+Q is the keystroke most people press to
  clear a window off the screen, not a decision to stop the thing
  running. Quitting is Cmd+Option+Q, still in the app menu where anybody
  would look for it, and still the Quit button in the menu bar's popover.

## 1.7.0

- **The detail pane counts the remarks on the diff.** It said "0 comments"
  over a review carrying forty of them, because the number it showed was
  GitHub's count for the conversation tab — a different thing, and nought
  on most pull requests that are reviewed rather than discussed. The pane
  leads with the conversations on the diff where there are any, which is
  what the file list beside the diff counts too, and falls back to the
  conversation where there are none. The tooltip gives both.
- **A file in the detail pane looks like something to press.** The rows
  opened the diff and said so only by being blue, in a pane full of blue
  text that is not a target. Each row ends in a chevron now, and the
  pointer becomes a hand over it.
- **A Review button opens the diff** from the Files heading, without
  having to pick a file to start at first.

- **Everything the app draws can be read on what it draws it on.** The
  colours were the system's own, which are tuned to stand out on a
  control rather than to be read as small text. Measured in light mode: a
  green tick at 2.2 to one, a yellow check at 1.5, an ageing timestamp at
  2.3, a linked pull request's number at 2.2, and the name on an issue
  type at 1.4 against the wash of its own colour. On the grey of a
  selected row, lower still; in a diff, a comment came in at 3.3 over the
  band behind a removed line.

  The hues are unchanged — a string is still red, a warning still orange
  — but each has been walked along its own brightness, darker in light
  mode and lighter in dark, until it clears 4.5 to one against every
  ground it is actually drawn on: the page, a selected row, both of a
  diff's tinted bands, and the wash a chip lays under its own name. One
  palette now, where four files used to choose separately.

  A test measures all of it, in both themes, so the next change to a
  colour has to clear the bar too.
- An issue type's chip takes its wash from the plain hue and its name
  from the weighted one. The two used to be the same colour at two
  strengths, which is why a yellow type read at 1.4 to one.
- The second line of a selected row is readable in dark mode, where the
  system's secondary grey fell to 3.3 against the selection — the one
  place a row is not drawn on the page's own colour.
- A comment in a diff is a grey that can be read. The system's secondary
  label came in at 3.3 to one over the band behind a removed line, and a
  comment is often the line explaining what the change is for.
- For development: `--theme dark` and `--theme light` draw the app in one
  theme whatever the Mac is set to, so both can be looked at without
  changing a system-wide preference.
- **A mention leads the pane it arrives in.** The remark that named you
  sat among twenty comments under a description that is usually a
  template, so the one thing in the pane addressed to you was the last
  thing you found. It comes first now, under its own heading, and stays
  in its place in the thread below.
- **The mentions list says what was said.** A row gave the title of the
  thread and nothing of the remark — which is the content being reacted
  to. It carries the first line of the comment now, with an `@` where
  that line really is the one naming you. GitHub hands out the thread's
  latest comment rather than the one that mentioned you, and sometimes
  those differ; the row says `@` only when it can tell.
- A pull request template's notes to the author are hidden, as GitHub
  hides them. They are written between `<!--` and `-->` and run to a
  paragraph, and the pattern that was meant to remove them could not
  match across lines — so every description opened with a block of
  instructions meant for somebody else, `-->` and all.

## 1.6.1

- **A linked number is visible again on the row you have selected.** It
  was drawn in `.secondary`, and inside a selected row SwiftUI resolves a
  hierarchical style against the selection — so the badge came out white
  on white. The same trap `ReviewDecision.tint` has carried a warning
  about since it was written; the colours are concrete now.
- **The conversation count beside a file matches what the diff shows.**
  It counted only what was still open, while the diff draws resolved
  conversations too, folded to a line — so a file showing two could say
  one, and a file whose remarks had all been settled said nothing at all.
  It reads `1/4` where those differ and `4` where they do not, and it is
  grey rather than blue once nothing is waiting on you.
- **A conversation the list counts is drawn somewhere.** Two ways it was
  not: a file GitHub sends no diff for kept its badge and showed only the
  line saying it had no diff, and a remark on a line outside the hunks
  GitHub chose to send was handed to the view and passed over in silence.
  Both are gathered at the file's header now, where the outdated ones
  already were.

## 1.6.0

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
