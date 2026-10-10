# MDM Inspector — Agent Handoff

## Project

- Path: `/Users/user/Projects/MDMInspector`
- Public repository: `https://github.com/superjaegermaster/MDMInspector`
- Current branch: `main`
- Current commit: `eadd563` — `Group MDM products into one dashboard topic (#22)`
- Working tree: clean at handoff
- Installed app: `/Applications/MDM Inspector.app`
- Supported architecture: Apple Silicon / `arm64`
- Toolchain: Swift 6.4, Swift Package Manager, macOS 14 minimum, Command Line Tools; full Xcode is not required.

## Product purpose

MDM Inspector is a native, local-only macOS troubleshooting workbench for investigating “What happened on this Mac?”. It collects local macOS, Apple MDM, Workspace ONE, Intune, Jamf, Kandji, ManageEngine, N-able, Defender, Platform SSO, identity and related evidence into Dashboard, Timeline, Inspector and Capabilities views.

Important constraints:

- No telemetry, cloud backend or persistent database.
- Preserve raw records; do not fabricate paths or root-cause claims.
- Missing products should be reported as absent, not as permission failures.
- SCCM and Omnissa Horizon are intentionally excluded.
- Workspace ONE Intelligent Hub belongs under Workspace ONE, not a separate category.
- The app is ad-hoc signed and not notarized; downloaded users may need Control-click → Open once.
- Apple Silicon only is intentional.

## Current behavior

### Snapshot loading

- The app uses explicit historical snapshots only; live mode has been removed completely.
- Default opening timeframe is **Last 5 minutes** (`InspectorModel.timeRange = .m5`).
- Explicit launch arguments remain available:
  - `-startView dashboard|timeline|capabilities`
  - `-timeRange 5m|15m|30m|1h|4h|24h`
  - `-displayMode grouped|detailed|raw`
- Refresh is user-triggered; there is no background polling or automatic timeline following.

### MDM topic grouping

Dashboard activity and grouped Timeline now combine these under one `MDM` topic:

- Apple MDM
- Kandji
- Microsoft Intune
- Workspace ONE
- Jamf Pro
- Mosyle

The original vendor/source labels remain in event details and Inspector views. MDM filtering uses `LogEvent.matches(.mdm)` and includes the vendor categories.

### Interface/documentation

- README no longer contains the “Screenshots and tests” or “Test checklist” sections.
- README download name is `MDM-Inspector.app.zip`; do not reintroduce `Apple-Silicon` into the app or ZIP filename.
- Only one GitHub release currently exists: `v0.1.0`, marked Latest.
- Release assets: `MDM-Inspector.app.zip`, `MDM.Inspector-0.1.dmg`, `MDM.Inspector-0.1.pkg`, `INSTALL.txt`.

## Build and run

From the project root:

```zsh
swift build -c release
./build_app.sh
open "build/MDM Inspector.app"
```

Install locally:

```zsh
rm -rf "/Applications/MDM Inspector.app"
cp -R "build/MDM Inspector.app" /Applications/
open "/Applications/MDM Inspector.app"
```

The build script assembles the app bundle, copies resources and icon metadata before signing, signs ad hoc, and verifies the signature. Never modify `Info.plist` or bundle contents after signing.

## Verification

```zsh
swift run -c release MDMInspectorSelfTest
codesign --verify --deep --strict "build/MDM Inspector.app"
git status --short
gh run list --limit 5
```

CI is authoritative for arm64 GitHub builds. The local self-test exercises real unified logs and may have machine-specific evidence differences. Do not turn a local absence into a product failure without checking CI and the collector’s documented-path behavior.

## Packaging and publishing

Installer script:

```zsh
./make_installer.sh
```

The release workflow is `.github/workflows/release.yml`. It runs on an arm64 macOS runner, builds the app, packages ZIP/DMG/PKG, and uploads release assets. Trigger manually with:

```zsh
gh workflow run "Build macOS release" --ref main -f tag=vX.Y.Z
```

Use the stable README URL:

```text
https://github.com/superjaegermaster/MDMInspector/releases/latest/download/MDM-Inspector.app.zip
```

Keep only one public release unless the user explicitly requests version history. To replace the single release, delete the old release/tag first, then run the workflow with the desired tag. The ZIP asset must remain exactly `MDM-Inspector.app.zip`.

## Icon

Selected design is proposal 3: detective silhouette, magnifying glass and log window.

- Master: `docs/assets/icon_1024.png`
- App icon: `Sources/MDMInspector/Resources/MDMInspector.icns`
- All standard macOS icon slots are generated with `iconutil`.
- The previous sizing bug came from a large unused top margin in the master artwork. Keep the artwork centered and filling the square canvas.
- Verify the actual `.icns`, not only the PNG, after rebuilding.

## Key files

- `Sources/MDMInspector/App/InspectorModel.swift` — state, default timeframe, refresh, filtering, Dashboard/Timeline topic grouping.
- `Sources/MDMInspector/Model/LogEvent.swift` — categories, classification, MDM matching and source labels.
- `Sources/MDMInspector/Model/TimeRange.swift` — supported ranges.
- `Sources/MDMInspector/Views/DashboardView.swift` — activity and recent errors.
- `Sources/MDMInspector/Views/TimelineView.swift` — detailed/grouped/raw timeline.
- `Sources/MDMInspector/Views/CapabilitiesView.swift` — capability grouping and permission status.
- `Sources/MDMInspector/Collectors/CollectorRegistry.swift` — registered evidence sources.
- `Sources/MDMInspector/Collectors/UnifiedLogProbe.swift` — cached honest unified-log probe.
- `Sources/MDMInspector/Collectors/FileLogCollector.swift` — actual-read file classification.
- `Sources/MDMInspectorSelfTest/main.swift` — executable regression/self-test suite.
- `build_app.sh` — app bundle build/sign/verification.
- `make_installer.sh` — PKG/DMG packaging.
- `.github/workflows/ci.yml` — CI build/self-test.
- `.github/workflows/release.yml` — arm64 release packaging.
- `README.md` — public project documentation and stable download link.
- `docs/INTERFACE.md` — interface behavior documentation.

## Known warnings and caveats

SwiftPM currently reports two unhandled resource files (`Info.plist` and `MDMInspector.icns`) because they are copied by the custom bundle script; this is an existing warning, not a build failure.

Ad-hoc signatures work locally but are not equivalent to Developer ID signing/notarization. Warning-free distribution to other Macs requires an Apple Developer ID certificate and notarization.

Do not guess vendor log paths. Confirm paths against vendor documentation before adding collectors. Workspace ONE paths already include current AirWatch/Munki/Hub locations and intentionally do not include the Linux-only `/var/log/ws1-hub/` path.

## Recent merged changes

- `#22` — MDM products merged into one Dashboard/Timeline MDM topic.
- `#21` — Removed README screenshots/tests sections.
- `#20` — Simplified release ZIP/app naming.
- `#19` — Five-minute default and MDM sidebar consolidation.
- `#18` — Corrected icon artwork sizing.
- `#17` — Adopted detective/log icon proposal 3.
- `#16` — Removed live mode completely.
