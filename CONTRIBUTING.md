# Contributing

## Issues and pull requests

| You want to | Use |
|---|---|
| Suggest a feature, report a bug, ask a question | Issue |
| Propose a code change | Pull request |

An issue is a conversation; a pull request is an edit to a file. They usually
pair up: someone opens an issue, someone else proposes a fix in a PR that closes
it.

Usage questions go in Discussions. Issues stay easier to search that way.

## Reporting a bug

A bug means the app showed you something untrue: a wrong number, a record that
isn't in the original log, a source claiming data it didn't read, or a product
reported missing when it's installed.

Paste the raw evidence. Open the event, copy the Raw Evidence box, put it in the
issue. That turns a week of investigation into an afternoon.

Strip customer names, hostnames and IP addresses first. The bug template asks you
to.

## Adding a log source

The most useful contribution, and easy to get right. A source is one entry in
`Collectors/CollectorRegistry.swift`.

Three things to get right:

**Use the vendor's documented path.** The obvious guess is usually wrong.
`/Library/Logs/JAMF` doesn't exist — the Jamf client log is
`/var/log/jamf.log`. Read the docs.

**Keep the original record.** It goes in `rawRecord` verbatim. Don't swap a log
line for your interpretation of it.

**Say what you didn't read.** If a source caps, windows or skips anything, that
goes in a `DiagnosticEvent`. A capped read that looks complete is the worst bug
this project can ship.

Add a self-test assertion for the path.

## What won't be merged

- Evidence that isn't there: guessed executable paths, invented timestamps,
  diagnoses the log doesn't support
- Automatic collapsing of repetitive events
- Automatic root-cause claims, loop detection, health scores
- Anything that sends data off the machine

Not style objections. The whole value of the tool is that you can trust it and
get back to the original record.

## Building

```zsh
./build_app.sh
swift run -c release MDMInspectorSelfTest
```

The self-test runs the real collectors against the real Mac. Run it before
opening a PR. A change that slows a collector or inflates memory shows up there
even when it looks fine in the UI.

## Screenshots

```zsh
python3 tools/capture_screenshots.py
```
