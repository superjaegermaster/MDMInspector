# The interface

A walk through each screen and what it's good for. Figures are from a live run on
macOS 26: 40 collectors, roughly 21,000 events in a five-minute snapshot.

## Launching

The app opens on the Dashboard. First it reads every source for the selected
range, which takes a few seconds on a real Mac:

```
●  Unified Log — Read 12,418 records              14,203 logs    62%
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

The count is the number of records collectors have actually streamed, not a
placeholder. A self-test asserts it ends up exactly equal to the loaded event
count, so it can't quietly become decoration. The bar only moves forward: a
source that can't estimate its work still advances it when it finishes.

The Dashboard is a snapshot, not a feed. Refresh reloads it.

## Dashboard

Counts for the range, the most recent errors, and activity per source.

| Card | Example |
|---|---|
| Events | 21,054 |
| Errors | 395 |
| Warnings | 0 |
| Sources | 8 |

Clicking an error opens that event in the Timeline with the Inspector on it,
which is usually how an investigation starts. Clicking a bar in *Activity by
Source* filters the timeline to that category.

It's descriptive on purpose. No health score, no ranking by severity, no claims
about cause.

## Timeline

Three panes: sources on the left, events in the middle, Inspector on the right.

Each row carries a millisecond timestamp, a severity glyph, a source dot, the
message, then process, source, event type and subsystem. The milliseconds
matter — several processes usually react inside the same second, and without
them you can't tell which came first.

### Display modes

| Mode | Shows |
|---|---|
| Grouped | events collapsed under their process |
| Detailed | one row per event (the default) |
| Raw | the original log record |

All three render every event that passed the filters. Grouping reorders, it never
collapses, so a 1%…100% download stays 100 rows. Nothing is dropped for being
repetitive.

### Filtering

Search covers message, process, executable path, subsystem, category and source;
all terms have to match, so `installer failed` narrows. The Severity menu filters
by level. The Sources sidebar filters by category, and below it the processes
discovered in this snapshot narrow it further — unrecognised processes included.

The status bar shows loaded and shown counts side by side, so a filter is never
hiding something without saying so.

## Inspector

Selecting an event fills the right-hand pane with its fields and the record
behind them.

- **Sources** can list more than one category. Company Portal is the usual
  case: an app-install record is `Microsoft Intune`, an extensible-SSO
  registration record is `Microsoft Intune · Platform SSO`. Either filter finds
  it.
- **Possible areas to investigate** appears for errors, and says it isn't a
  diagnosis. A failed install suggests package integrity, code signing,
  installer prerequisites, disk space.
- **Related records** lists other events from the same process.
- **Raw evidence** is the original line, selectable and copyable with `⇧⌘C`.

## Capabilities

Every registered source with its real status: available, permission required
(with the System Settings path and the fix), or not present on this Mac. The
last one isn't a permissions error and isn't reported as one.

Also records the privacy position: no telemetry, no analytics, no network calls,
logs read on demand and held in memory.

## Snapshot workflow

The app works from explicit historical snapshots. Choose a time range, press
Refresh, and inspect the resulting records. There is no background tail or
continuously updating mode; a refresh is the deliberate boundary for each
investigation.

## Time range

5 minutes, 15 minutes, 30 (default), 1 hour, 4 hours, 24 hours. Presets only;
custom ranges aren't built.

## What it won't tell you

- The cause. No root cause, no "stuck", no "loop".
- What the server did. Local evidence shows a command arrived; it stops there.
- A file path it hasn't seen. Unrunning processes show `—`.
- That it read everything, when it didn't.

## Regenerating the images

```zsh
python3 tools/capture_screenshots.py
```

Views are selected with `-startView`, `-displayMode`, `-timeRange` and
`-selectEvent firstError`. Needs an unlocked screen.
