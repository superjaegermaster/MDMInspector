# MDM Inspector — the interface, view by view

A walk through every screen and control, and — more usefully — what each one is
good for. All figures below are real output from a live run on a Mac (macOS 26,
40 collectors registered, ~20,700 events in the last 30 minutes).

> **Screenshots are generated, not mocked up.** Run
> `python3 tools/capture_screenshots.py` (needs an unlocked screen) to refresh
> `docs/screenshots/`. Every view is opened through the app's launch arguments
> rather than by synthetic clicks, and each capture is gated on the status bar
> actually reporting loaded events — so a half-loaded UI can never be
> committed. All four images below are real runs on a live Mac.

---

## 0. What happens on launch

The app opens on the **Dashboard**, never straight into the raw log. It first
reads the selected historical range from every source — which on a real Mac
takes several seconds — and shows what it is doing while it works:

```
●  Unified Log — Read 12,418 records              14,203 logs    62%
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Three things make that bar trustworthy:

- **The count is real.** Every collector reports how many records it has
  actually streamed, and the model sums them. It is not a decorative ticker —
  the self-test asserts the running total ends up *exactly* equal to the number
  of events loaded.
- **The bar only moves forward.** Collectors that cannot estimate their work
  still advance the bar when they finish, so it never stalls or jumps back.
- **It says what it did not read.** If a range is capped, or a source only
  searched part of it, that is stated rather than quietly implied.

The bar then disappears; the dashboard is a **snapshot**, not a live feed. Press
**Refresh** (or change the time range) to reload it.

---

## 1. Dashboard — "what is this Mac doing?"

A factual summary of the selected range. Deliberately **descriptive, not
diagnostic**: there is no health score, nothing is ranked by importance, and no
claim is made about cause.

**Four counters**

| Card | Live example | Meaning |
|---|---|---|
| Events | 20,721 | Records in range, after filters |
| Errors | 293 | Severity Error or Fault |
| Warnings | 0 | Severity Warning |
| Sources | 8 | Distinct categories contributing |

**Recent Errors** — the most recent errors, each showing time, source, process,
message and type. **Click any row to jump straight to that event in the
Timeline** with the Inspector open on it. This is the usual way into an
investigation: notice something here, click it, keep reading.

**Activity by Source** — volume per category, as a bar chart. Click a bar to
filter the timeline to that source. Purely descriptive: a large *Other* bar
usually means unrecognised processes, which is information in itself rather than
a problem.

![Dashboard](screenshots/01-dashboard.png)

---

## 2. Timeline — the primary investigation surface

A three-pane Mac-native layout:

```
┌─────────────┬──────────────────────────────────┬──────────────────┐
│ Sources     │ Timeline                         │ Inspector        │
│             │                                  │                  │
│ All         │ 16:24:03.985 ✕ ⬤ Process name   │ INSTALLATION     │
│ macOS       │   message text…                  │ FAILED           │
│ MDM         │                                  │                  │
│ Microsoft   │ 16:24:03.940 • ⬤ Process name   │ DETAILS          │
│  Intune     │   message text…                  │  Timestamp  …    │
│ Platform SSO│                                  │  Sources   …     │
│ Jamf Pro    │                                  │                  │
│ Network     │                                  │ RAW EVIDENCE     │
└─────────────┴──────────────────────────────────┴──────────────────┘
```

**Event rows** carry, left to right: millisecond timestamp, severity glyph,
source colour dot, the message, and then process · source · event type ·
subsystem. Milliseconds matter — several processes usually react inside the same
second, and without that precision you cannot tell which came first.

### The three display modes

| Mode | Shows | Use it for |
|---|---|---|
| **Grouped** | Events collapsed under their process | "Show me everything this one process did" |
| **Detailed** | One row per event | Chronological reading — the default |
| **Raw** | The original log record, verbatim | Confirming anything, before quoting it |

![Timeline with the Inspector open](screenshots/02-timeline.png)

All three render **every** event that passed the filters. Grouping is
presentation, never deletion — the same 20,721 events are in each mode, and no
repeating event is ever collapsed. (A download at 1%…100% stays 100 rows.)

### Filtering

- **Search** covers message, process, executable path, subsystem, category and
  source — all words must match, so `installer failed` narrows rather than widens.
- **Sources sidebar** — click a category to filter. Below it, the **processes
  discovered** in this snapshot; click one to narrow further. Unknown processes
  appear here like any other.
- **Severity** menu — filter to errors, warnings, or both.
- The status bar always shows *loaded* vs *shown*, so a filter is never silently
  hiding evidence.

---

## 3. Inspector — the evidence

Selecting any event opens the right-hand pane. It never replaces the record with
a summary; it shows the record, plus the fields needed to find it in a raw log
later.

**Details** — Timestamp, Sources, Process, Executable, Subsystem, Category,
Event type, and which collector produced it.

**Sources** can list more than one category. Company Portal is the clearest
example: it is the Intune agent's user app *and* the host of the Microsoft
Enterprise SSO extension (`com.microsoft.CompanyPortalMac.ssoextension`) that
brokers Entra ID for Platform SSO. A Company Portal record about an app install
is listed as *Microsoft Intune*; a record about extensible-SSO registration is
listed as *Microsoft Intune · Platform SSO*, and either filter finds it.

**Possible areas to investigate** (errors only) — explicitly labelled as *not a
diagnosis*. For a failed install it suggests package integrity, code signing,
installer prerequisites, disk space. These are starting points, never a root
cause claim.

**Related records** — other events from the same process, for context.

**Raw evidence** — the original log line, selectable and copyable (`⇧⌘C`). This
is the point of the whole tool: whatever the UI suggests, you can always get
back to what the system actually wrote.

![Raw evidence view](screenshots/03-inspector.png)

---

## 4. Capabilities — what can be read, and why not

Every registered source with its real status:

- ✓ **Available**
- ⚠ **Permission required** — plus the exact System Settings path and the
  remediation steps
- ✕ **Not present on this Mac** — an honest "this product isn't installed", which
  is *not* a permissions error and never reported as one

![Capabilities](screenshots/04-capabilities.png)

Also documents the privacy stance: no telemetry, no analytics, no network calls,
logs read on demand and held in memory only.

---

## 5. Historical vs LIVE

| | Historical | LIVE |
|---|---|---|
| Shows | The selected range, as a snapshot | Records as they arrive |
| Updates | On **Refresh** only | Continuously |
| Timeline, filters, modes, Inspector | Same | Same |

LIVE is standard log-viewer behaviour: if you are at the bottom you follow new
records; scroll up and following stops; return to the bottom and it resumes.
There is no separate monitoring UI — it is the same timeline you already know.

---

## 6. Time range

5 minutes · 15 minutes · **30 minutes (default)** · 1 hour · 4 hours · 24 hours

Changing the range reloads the snapshot. These are presets on purpose; custom
date ranges are deferred in v0.1.

---

## What this tool will not do

Being explicit about the limits, because a troubleshooting tool that overreaches
is worse than none:

- It will **not** tell you the root cause, that something is "stuck", or that a
  loop is occurring.
- It reports **what the Mac knows**, not what you assume happened in the
  Workspace ONE or Intune console. If the local evidence shows a command arrived,
  it says the command arrived — nothing more.
- It will **not** fabricate a file path. If a process is not running, the
  executable shows `—`.
- It will **not** silently truncate. Capped reads say so, and say how much.
- No health score, no remote actions, no uploading, no persistent database.

---

## Regenerating the images

```zsh
python3 tools/capture_screenshots.py            # needs an unlocked screen
```

The script fails fast if the screen is locked rather than saving a picture of
the login screen, refuses to capture a view it could not bring to the front, and
waits for the status bar to report loaded events before each shot.

Views are selected with `-startView`, `-displayMode`, `-timeRange` and
`-selectEvent firstError` (which preselects an error so the Inspector is
populated without synthesised clicks).