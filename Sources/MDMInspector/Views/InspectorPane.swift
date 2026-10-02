import SwiftUI
import AppKit

/// Inspector sidebar (§20). Shows the event's own metadata and its raw evidence.
/// It never claims a root cause; it can point at where to look next.
public struct InspectorPane: View {
    @EnvironmentObject public var model: InspectorModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let event = model.selectedEvent {
                    header(event)
                    metadata(event)
                    if event.severity >= .error {
                        investigationAreas(investigationAreas(for: event))
                    }
                    relatedEvents(event)
                    rawEvidence(event)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No event selected").font(.system(size: 13, weight: .semibold))
                        Text("Select a timeline event to see its metadata and the original record it came from.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func header(_ event: LogEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(event.severity.glyph).foregroundStyle(event.severity.color)
                Text(event.severity.label.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(event.severity.color)
            }
            Text(event.message)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            // An event can span categories (e.g. Company Portal broker activity
            // is both an Intune and a Platform SSO concern), so show them all.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(event.sources.enumerated()), id: \.offset) { idx, c in
                    HStack(spacing: 6) {
                        Circle().fill(c.color).frame(width: 8, height: 8)
                        Text(c.label).font(.system(size: 11))
                    }
                }
            }
        }
    }

    private func metadata(_ event: LogEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DETAILS").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
            row("Timestamp", Stamp.full.string(from: event.timestamp), mono: true)
            row(event.sources.count > 1 ? "Sources" : "Source", event.sourceLabel)
            row("Process", event.process, mono: true)
            row("Executable", event.executablePath, mono: true, selectable: true)
            row("Subsystem", event.subsystem.isEmpty ? "—" : event.subsystem, mono: true, selectable: true)
            row("Category", event.category.isEmpty ? "—" : event.category)
            row("Event type", event.eventType)
            row("Collector", event.collectorID, mono: true)
        }
    }

    /// Factual hints only — never a root-cause claim.
    private func investigationAreas(for event: LogEvent) -> [String] {
        let m = event.message.lowercased()
        var areas: [String] = []
        if m.contains("install") || event.process.contains("installer") {
            areas += ["Package integrity", "Code signing / notarization", "Installer prerequisites", "Disk space and volume layout"]
        }
        if m.contains("profile") { areas += ["Profile payload validity", "MDM server reachability", "Scope and payload conflicts"] }
        if m.contains("command") { areas += ["Command delivery in the local MDM client", "Acknowledgement in mdmclient"] }
        if m.contains("download") { areas += ["Console-to-hub delivery", "Network path and proxy", "Local disk space"] }
        if m.contains("certificate") || m.contains("scep") { areas += ["SCEP / AD CS reachability", "Certificate payload scope", "Keychain state"] }
        if m.contains("enroll") || m.contains("check-in") || m.contains("checkin") {
            areas += ["Enrolment profile presence", "DEP / ABM assignment", "Network reachability to MDM"]
        }
        if areas.isEmpty {
            areas = ["Open the raw record below and the neighbouring events in the same time window."]
        }
        return areas
    }

    @ViewBuilder
    private func investigationAreas(_ areas: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("POSSIBLE AREAS TO INVESTIGATE")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
            Text("Not a diagnosis. Areas worth looking at, based on this record only.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            ForEach(areas, id: \.self) { a in
                HStack(alignment: .top, spacing: 5) {
                    Text("•").foregroundStyle(.secondary)
                    Text(a).font(.system(size: 11))
                }
            }
        }
    }

    @ViewBuilder
    private func relatedEvents(_ event: LogEvent) -> some View {
        let related = model.events
            .filter { $0.process == event.process && $0.id != event.id }
            .prefix(8)
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("RELATED RECORDS — \(event.process)")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                ForEach(Array(related)) { r in
                    Button { model.selectedEvent = r } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Text(Stamp.timeWithMillis.string(from: r.timestamp))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 78, alignment: .leading)
                            Text(r.message).font(.system(size: 11)).lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rawEvidence(_ event: LogEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("RAW EVIDENCE").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    model.copyRawRecord(event)
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain)
                    .help("Copy the original record")
            }
            Text(event.rawRecord)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false, selectable: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Group {
                if selectable {
                    Text(value).textSelection(.enabled)
                } else {
                    Text(value)
                }
            }
            .font(.system(size: 11, design: mono ? .monospaced : .default))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
