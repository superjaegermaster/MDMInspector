# MDM Inspector

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Something broke on a Mac. An app didn't install, a profile didn't apply, the Hub
looks wedged. The answer is on the Mac, but it's scattered:

```
/var/log/install.log                       macOS installer
Unified log (hubd, mdmclient, AirWatch)      Hub + macOS management events
/var/log/jamf.log                            Jamf client
/Library/Logs/Microsoft/Intune             Intune agent
~/Library/Logs/CompanyPortal.log           Company Portal
/Library/Application Support/AirWatch/Data/Munki/managed installs/logs/
                                             Workspace ONE ManagedSoftwareUpdate.log
/Library/Logs/DiagnosticReports            Hub/hubd crash reports
…plus Console.app, filtered by hand, every time
```

You read install.log, find nothing conclusive, pivot to Console, filter by
subsystem, wonder whether the failure was macOS or the agent that delivered the
package, go read that agent's own log, notice the timestamps nearly line up, and
start over.

Everything you need is on one machine. What's missing is the ordering, and
ordering is what scattered logs throw away.

**"What happened on this Mac?"** — MDM Inspector puts those logs on one
timeline, in order, to the millisecond. So you can see that the Hub download
finished at `10:42:48.014`, installer started at `10:42:48.391`, and it failed at
`10:42:52.123`. Three sources, one screen.

Run it on whatever Mac is in front of you. It reads that Mac and nothing else.
When it shows you an error, the original log line is always one click away.

Built for Apple, Workspace ONE, Intune and Jamf administrators: the person who
gets the call when something breaks, not the person watching a dashboard.

No API, no cloud backend, no telemetry, no database. It tells you what the Mac
knows, not what you assume happened in the console. If the local evidence shows a
command arrived, it says the command arrived. It won't claim the server acted on
it, because that evidence isn't here.

---

## Screenshots

### Dashboard

Counts, recent errors, activity by source. Click an error to jump to it in the
Timeline.

![Dashboard](docs/screenshots/01-dashboard.png)

### Timeline and Inspector

Sources on the left, events in the middle, Inspector on the right.

![Timeline and Inspector](docs/screenshots/02-timeline.png)

### Raw evidence

The original log record, selectable and copyable with `⇧⌘C`.

![Raw evidence](docs/screenshots/03-inspector.png)

### Capabilities

What each source can actually read on this Mac.

![Capabilities](docs/screenshots/04-capabilities.png)

---

## Build and run

```zsh
./build_app.sh            # release build → build/MDM Inspector.app
./build_app.sh --debug
open "build/MDM Inspector.app"
```

Check the collectors against this Mac:

```zsh
swift run -c release MDMInspectorSelfTest
```

macOS 14+ and the Swift 6 toolchain. Command Line Tools are enough — there's no
Xcode dependency.

## Downloading a ready-to-run app

A pre-built Apple Silicon release is published on the [GitHub Releases](https://github.com/superjaegermaster/MDMInspector/releases) page. Download `MDM-Inspector-Apple-Silicon.app.zip` for the simplest install, unzip it, and move `MDM Inspector.app` to Applications. A DMG and PKG are included for users who prefer those formats.

The release is built on an Apple Silicon GitHub runner and contains an arm64
binary. It is ad-hoc signed, not notarized with an Apple Developer ID. macOS
therefore asks for a one-time validation: Control-click `MDM Inspector.app`,
choose **Open**, then confirm **Open**. This is the expected validation for the
pre-built download, not a build step. The same warning applies to the DMG and
PKG copies.

A future Developer ID signing and notarization setup can remove that validation
step. It requires an Apple Developer Program membership and a certificate; the
source code does not need to change.

## Status

Working: the three views, 55 sources covering macOS MDM internals, Workspace ONE,
Intune, Jamf, Platform SSO and other MDM vendors, plus the permissions centre.
Not built, on purpose: correlation, loop detection, root-cause claims. See
[Known limits](#known-limits).

## What it reads

| Source | Where |
|---|---|
| Unified Log | `OSLogStore(scope: .system)` — every process, every subsystem |
| **macOS MDM & platform** | unified: `com.apple.ManagedClient`, `mdmclient`, `installcoordination`, `mobileasset`, `SoftwareUpdate`, `amfi`; plus `/Library/Logs/ManagedClient/ManagedClient.log` |
| Running Processes | kernel process list; gives name + executable path |
| macOS | `/var/log/install.log`, `system.log`, `appfirewall.log`, `wifi.log`, `asl`, `DiagnosticReports` |
| **Microsoft Intune** | `/Library/Logs/Microsoft/Intune`, `~/Library/Logs/Microsoft/Intune`, `IntuneScripts/`, `~/Library/Logs/CompanyPortal.log` |
| Intune (unified log) | `com.microsoft.intune*`, processes `IntuneMDMDaemon` / `IntuneMDMAgent` / `IntuneMMA` |
| **Jamf Pro** | `/var/log/jamf.log`, `jamfinstall.log`, `jamf_setup.log`, `JAMFChangeManagement.log`, `/usr/local/jamf/bin` |
| Jamf (unified log) | `com.jamf*`, processes `jamf` / `JamfDaemon` / `JamfAgent` |
| **Platform SSO** | `com.apple.AppSSO`, `com.apple.extensiblesso`, `com.apple.heimdal`, plus the vendor extension (Microsoft, Okta); `SSOExtension`, `AppSSOAgent`, `KerberosExtension`, `swcd` |
| Workspace ONE / Intelligent Hub | unified `hubd`, `awagent`, `mdmclient`, AirWatch/Omnissa subsystems; `/Library/Logs/DiagnosticReports` for `Intelligent Hub*.crash` and `hubd*.crash`; `/Library/Application Support/AirWatch/Data/Munki/managed installs/logs/ManagedSoftwareUpdate.log`; `InstallInfo.plist`, `ManagedInstallReport.plist`, and `AppStatuses_WS1.plist` |
| Kandji | unified `io.kandji*`; `/Library/Logs/Kandji` |
| ManageEngine | `/Library/UEMS_Agent/logs` |
| N-able | `/Library/Logs/N-central Agent`, `/var/log/N-able/N-agent` |
| Microsoft Defender for Endpoint | `/Library/Logs/Microsoft/mdatp` |
| Others | MSI, Adobe, Zscaler, Cisco, OneDrive, Microsoft AutoUpdate |

Paths come from each vendor's documentation. Workspace ONE's macOS source list in
[Omnissa's Device-Side Logging guide](https://docs.omnissa.com/TroubleshootingandLoggingGuide-VSaaS/WorkspaceONEUEMDevice-SideLogging)
identifies `ManagedSoftwareUpdate.log`, the Managed Installs status plists,
`AppStatuses_WS1.plist`, and Hub crash reports. The `/var/log/ws1-hub/` paths
shown elsewhere in that document are under its Linux section, so MDM Inspector
does not register them for macOS. The obvious guess is often wrong —
`/Library/Logs/JAMF` doesn't exist; the client log is `/var/log/jamf.log`. A
self-test pins these distinctions so they can't regress.

Adding a source is one entry in `Collectors/CollectorRegistry.swift`. It then
shows up in the sidebar, the filters and the Capabilities tab with no other
changes.

### One event, two sources

Company Portal is both the Intune agent's user app and the host of the
Enterprise SSO extension (`com.microsoft.CompanyPortalMac.ssoextension`) that
brokers Entra ID for Platform SSO. Bucketing it either way hides it from someone.

So `LogEvent.sources` is a list. A Company Portal record about an app install is
Intune. A record about extensible-SSO registration is
`Microsoft Intune · Platform SSO`, and filtering either category finds it.

## Architecture

```
Sources/
  MDMInspector/            library: models, collectors, views
    Model/                 LogEvent, Severity, SourceCategory, TimeRange
    Collectors/            LogCollector protocol + implementations
    App/                   InspectorModel, the view state
    Views/                 Dashboard, Timeline, Inspector, Capabilities
  MDMInspectorApp/         @main shim
  MDMInspectorSelfTest/    headless collector checks
```

`LogEvent` doesn't know or care where a record came from, so new collectors
don't touch the UI.

## What it won't do

- Report a cause. No "root cause", no "stuck", no "loop detected". Errors get a
  list of things worth checking, labelled as such.
- Invent an executable path. If the process isn't running, it prints `—`.
- Claim more than it read. Capped or windowed reads say so, with how much.
- Drop evidence. Grouping reorders, it doesn't collapse. Grouped, Detailed and
  Raw all show the same event count.
- Call an uninstalled product a permissions problem.

## Loading

A load takes a few seconds, so there's a bar under the toolbar: the source being
read, a live count of records found, and a percentage where one can be estimated.
The dot and bar fill pulse gently.

The count is real. Each collector reports what it has actually streamed and the
model sums them, and a self-test asserts the running total ends up equal to the
number of events loaded. Sources that can't estimate still advance the bar when
they finish, so it never stalls or goes backwards.

Vendor unified-log sources only search the last few minutes when none of their
processes are running, and say so.

## Screenshots and tests

```zsh
python3 tools/capture_screenshots.py    # needs an unlocked screen
```

Views are opened with launch arguments (`-startView`, `-displayMode`,
`-timeRange`) rather than clicks, so runs are repeatable. The script bails if
the screen is locked instead of photographing the login screen.

Before opening a PR:

```zsh
./build_app.sh
swift run -c release MDMInspectorSelfTest
```

## Test checklist

1. Launch: bar appears with a climbing count, then the Dashboard loads
2. Change the range 5m → 24h; counts move, no hang at 24h
3. Timeline: Grouped / Detailed / Raw show the same event count
4. Select an event; Inspector shows timestamp, process, executable, subsystem,
   category, severity, raw record
5. `⇧⌘C` copies the raw record
6. Search filters on message, process, path, subsystem, category
7. Sidebar filters by source, then by discovered process
8. LIVE appends; scrolling up stops following
9. Capabilities lists every source with its real status
10. If Unified Log says *Permission required*: grant Full Disk Access, quit,
    reopen

## Known limits

No custom date ranges, no automatic collapsing of repetitive events, no health
scores, no root-cause claims, no loop detection, no PPPC payload generation, no
remote investigation. The unified log needs Full Disk Access; every other source
degrades quietly and says which one failed.

## Contributing

New to this, or new to GitHub? [CONTRIBUTING.md](CONTRIBUTING.md) explains the
distinction that trips people up:

- **Issues** — feature requests, bugs, questions
- **Pull requests** — a proposed change to the code

Bug and feature forms ask for what makes them actionable, including the raw log
line. Usage questions are better in Discussions.

## More detail

[docs/INTERFACE.md](docs/INTERFACE.md) walks through every view and control.
