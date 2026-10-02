import SwiftUI
import AppKit

/// Capabilities / Permissions center (§27, §28). Status per source, with the
/// concrete System Settings path when a permission is missing. MDM Inspector
/// cannot grant PPPC permissions itself and does not try to.
public struct CapabilitiesView: View {
    @EnvironmentObject public var model: InspectorModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Capabilities").font(.system(size: 22, weight: .semibold))
                    Text("What this Mac lets MDM Inspector read. Local only.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 18) {
                    sourcesList
                    remediation
                }
            }
            .padding(18)
        }
    }

    private var sourcesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sources").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Re-check") { model.refreshCapabilities() }
            }
            VStack(spacing: 0) {
                ForEach(model.collectors, id: \.id) { c in
                    let status = model.capabilities[c.id] ?? .unavailable("Unknown")
                    HStack(alignment: .top, spacing: 9) {
                        statusIcon(status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.displayName).font(.system(size: 12, weight: .medium))
                            Text(c.detail)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 12)
                        Text(status.label)
                            .font(.system(size: 11))
                            .foregroundStyle(statusColor(status))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 300, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    Divider()
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var remediation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("If a source shows “Permission required”").font(.system(size: 14, weight: .semibold))
            Text("""
            MDM Inspector cannot grant privacy permissions to itself. The missing \
            capability has to be authorised by an administrator, either manually here \
            or by deploying a PPPC profile through Workspace ONE.
            """)
            .font(.system(size: 11)).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Manual route").font(.system(size: 12, weight: .semibold))
                Text("1. System Settings → Privacy & Security → Full Disk Access")
                Text("2. Click + and add MDM Inspector.app")
                Text("3. Enable the toggle, then quit and reopen MDM Inspector")
                Text("4. Press Re-check here")
            }
            .font(.system(size: 11))

            VStack(alignment: .leading, spacing: 8) {
                Text("Managed route (PPPC profile)").font(.system(size: 12, weight: .semibold))
                Text("""
                A PPPC payload can grant Full Disk Access to MDM Inspector by \
                bundle id and can be delivered as a configuration profile through \
                Workspace ONE. Payload generation is deferred past the first MVP; \
                this page only records the requirement.
                """)
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Privacy stance").font(.system(size: 12, weight: .semibold))
                Text("No telemetry, no analytics, no network calls. Logs are read on demand and held in memory only. Nothing is written to a database.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 400, alignment: .leading)
    }

    @ViewBuilder
    private func statusIcon(_ status: CapabilityStatus) -> some View {
        switch status {
        case .available:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .permissionRequired:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .unavailable:
            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        }
    }

    private func statusColor(_ status: CapabilityStatus) -> Color {
        switch status {
        case .available: return .secondary
        case .permissionRequired: return .orange
        case .unavailable: return .secondary
        }
    }
}
