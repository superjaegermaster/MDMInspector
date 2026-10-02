# Contributing

Thanks for looking. This tool is small and evidence-driven, so contributions that
fit are ones that make the evidence easier to reach, or that make a claim more
honest.

## Issues vs pull requests

The distinction trips people up, so, briefly:

| You want to… | Use |
|---|---|
| Suggest a feature, report a bug, ask a question | **Issue** |
| Propose a change to the code | **Pull request** |

An issue is a conversation. A pull request is a proposed edit to a file. They
link together all the time — open an issue, someone proposes a fix in a pull
request that closes it.

Usage questions go in **Discussions** rather than Issues; Issues are easier to
search later when they hold real bugs and real feature requests.

## Reporting a bug

A bug means the app showed you something untrue: a wrong value, a record that
isn't in the original log, a source claiming data it didn't read, or a product
reported as missing when it's installed.

The **raw evidence** is what makes a bug fixable in minutes instead of days. In
the Inspector, open an event and copy the Raw Evidence box into the report.

Please strip customer names, hostnames and IP addresses from anything you paste.

## Adding a log source

This is the most useful contribution, and the easiest to get right.

A source is one entry in `Collectors/CollectorRegistry.swift`. Three rules:

1. **Use the vendor's documented path.** Do not guess. If you are adding
   Microsoft Intune or Jamf support, read their docs — the obvious path is
   frequently wrong (`/Library/Logs/JAMF` does not exist; the client log is
   `/var/log/jamf.log`).
2. **Keep it evidence-first.** The original record is always preserved verbatim
   in `rawRecord`. Never replace a log line with an interpretation.
3. **Say what you did not read.** If a source caps, window or skips data, it must
   say so in a `DiagnosticEvent`. A capped read that claims to be complete is
   the worst bug this project can ship.

Add a self-test assertion for the path, so a plausible-but-wrong guess gets
caught rather than silently returning nothing.

## What we won't merge

- Anything that fabricates evidence: guessed executable paths, invented
  timestamps, "diagnosed" errors the log doesn't actually say
- Automatic collapsing of repetitive events
- Automatic root-cause claims, loop detection or health scores
- Anything that sends data off the machine. There is no telemetry, and it is
  staying that way

These aren't style objections. The entire value of the tool is that an admin can
trust it and get back to the original record.

## Building

```zsh
./build_app.sh                          # release build → build/MDM Inspector.app
swift run -c release MDMInspectorSelfTest   # 63 checks against the live system
```

The self-test runs the real collectors against the real Mac. Please run it before
opening a pull request — a change that slows a collector or inflates memory will
show up there, even though it looks fine in the UI.

## Screenshots

```zsh
python3 tools/capture_screenshots.py     # needs an unlocked screen
```