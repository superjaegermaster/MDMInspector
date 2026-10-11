# Interface guide

MDM Inspector reads local logs into a refreshable snapshot. It does not stream continuously or query an MDM server.

## Dashboard

Shows event, error, and warning counts plus recent errors and activity by source. Select an error to open it in the Timeline.

## Timeline

- **Sources** filters by category; unrecognized processes remain visible under Other.
- **Search** matches message, process, executable path, subsystem, category, and source. Severity and process filters are also available.
- **Grouped**, **Detailed**, and **Raw** change presentation; they do not discard matching events.
- The status bar distinguishes loaded records from records currently shown by filters.

## Inspector

Selecting an event shows its timestamp, source, process, subsystem, category, event type, related records, and original raw evidence. Error events include possible areas to investigate, explicitly not a diagnosis.

### Optional Apple local-model insight

For an error-level event, choose **Ask Apple local model for insight**. It is optional and user-triggered. The app checks for macOS 27+, accepted Apple Foundation Models terms (`fm license --status`), and model availability. To accept terms, run `fm license` yourself in Terminal.

The model receives a bounded summary of that event—not its raw record, executable path, or neighboring events. The message itself can contain sensitive text. Responses must be treated only as **AI-generated hypotheses, not findings or root-cause determinations**; review the original evidence and independently verify any suggested safe, reversible checks.

## MDM coverage

Dedicated local log sources: **Apple MDM, Microsoft Intune, Omnissa Workspace ONE (Intelligent Hub), Jamf Pro, Kandji, ManageEngine, and N-able**. Unified-log/process classification also recognizes **Addigy, Cognito, Hexnode, Meraki, Mosyle, Scalefusion, and SimpleMDM** when those records are present. These are read-only evidence sources, not device-management controls. Platform SSO, macOS, app-install, security, and process records provide additional context.

## Capabilities and limits

Capabilities shows each source's actual status: available, permission required, or not present. Missing files are not reported as permission failures. Unified-log access requires Full Disk Access; other sources may be unavailable depending on the Mac and installed agents.

Snapshots cover preset time ranges. Press **Refresh** to load again. The app does not determine root cause, infer server actions, or automatically correlate events. See the [README](../README.md) for build and download instructions.
