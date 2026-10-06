import SwiftUI
import AppKit

/// Capabilities / Permissions center. Apple-provided sources are grouped by
/// the thing they describe; vendor sources are grouped by the product that
/// owns them. This makes "what is blocked?" answerable without scanning a
/// 55-row flat list.
public struct CapabilitiesView: View {
    @EnvironmentObject public var model: InspectorModel

    private struct CapabilityGroup: Identifiable {
        let title: String
        let subtitle: String
        let collectors: [any LogCollector]
        var id: String { title }
    }

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

    private var capabilityGroups: [CapabilityGroup] {
        let grouped = Dictionary(grouping: model.collectors) { group(for: $0.id) }
        let order = [
            "Built-in macOS · System and diagnostics",
            "Built-in macOS · MDM and profiles",
            "Built-in macOS · Install and network",
            "Workspace ONE UEM",
            "Microsoft Intune",
            "Jamf Pro",
            "Platform SSO and identity",
            "Kandji",
            "ManageEngine",
            "N-able",
            "Microsoft Defender for Endpoint",
            "Other installed software"
        ]
        return order.compactMap { title in
            guard let sources = grouped[title], !sources.isEmpty else { return nil }
            return CapabilityGroup(title: title, subtitle: subtitle(for: title), collectors: sources)
        }
    }

    private func group(for id: String) -> String {
        switch id {
        // Apple platform sources: group by troubleshooting topic, not by an
        // invented vendor. These are part of macOS itself.
        case "unified", "processes", "diagnostics-reports":
            return "Built-in macOS · System and diagnostics"
        case "macos-mdm-unified", "macos-managedclient-log":
            return "Built-in macOS · MDM and profiles"
        case "install-log", "install-log-0", "system-log", "appfirewall", "wifi-log", "daily-out", "asl":
            return "Built-in macOS · Install and network"

        // Everything below is owned by a named product/MDM, so its files and
        // unified-log view stay together even when the component is called Hub,
        // Company Portal, an agent, or an extension.
        case let x where x.hasPrefix("ws1-"):
            return "Workspace ONE UEM"
        case let x where x.hasPrefix("intune-") || x.hasPrefix("ms-"):
            return "Microsoft Intune"
        case let x where x.hasPrefix("jamf-"):
            return "Jamf Pro"
        case let x where x.hasPrefix("platformsso-"):
            return "Platform SSO and identity"
        case let x where x.hasPrefix("kandji-"):
            return "Kandji"
        case let x where x.hasPrefix("manageengine-"):
            return "ManageEngine"
        case let x where x.hasPrefix("nable-"):
            return "N-able"
        case "mde-logs":
            return "Microsoft Defender for Endpoint"
        default:
            return "Other installed software"
        }
    }

    private func subtitle(for title: String) -> String {
        switch title {
        case "Built-in macOS · System and diagnostics":
            return "Apple Unified Log, process inventory and crash reports"
        case "Built-in macOS · MDM and profiles":
            return "Apple profile, MDM command and software-update evidence"
        case "Built-in macOS · Install and network":
            return "Installer, firewall, Wi-Fi and legacy system logs"
        case "Workspace ONE UEM":
            return "Intelligent Hub, AirWatch/Munki and Workspace ONE components"
        case "Microsoft Intune":
            return "Intune agents, Company Portal and Microsoft support logs"
        case "Jamf Pro":
            return "Jamf client, installation, setup and Self Service logs"
        case "Platform SSO and identity":
            return "Apple, Microsoft, Okta and Kerberos SSO components"
        default:
            return "Registered local sources"
        }
    }

    private var sourcesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sources").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Re-check") { model.refreshCapabilities() }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(capabilityGroups) { group in
                    DisclosureGroup {
                        VStack(spacing: 0) {
                            ForEach(group.collectors, id: \.id) { c in
                                sourceRow(c)
                                if c.id != group.collectors.last?.id { Divider() }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: groupIcon(group.title))
                                .foregroundStyle(groupColour(group.title))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title).font(.system(size: 13, weight: .semibold))
                                Text(group.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(group.collectors.count)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceRow(_ c: any LogCollector) -> some View {
        let status = model.capabilities[c.id] ?? .unavailable("Unknown")
        return HStack(alignment: .top, spacing: 9) {
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
    }

    private func groupIcon(_ title: String) -> String {
        if title.hasPrefix("Built-in") { return "apple.logo" }
        if title == "Platform SSO and identity" { return "person.badge.key" }
        if title == "Workspace ONE UEM" || title == "Microsoft Intune" || title == "Jamf Pro" { return "building.2" }
        return "shippingbox"
    }

    private func groupColour(_ title: String) -> Color {
        if title.hasPrefix("Built-in") { return .blue }
        if title == "Workspace ONE UEM" { return .purple }
        if title == "Microsoft Intune" { return .blue }
        if title == "Jamf Pro" { return .green }
        return .secondary
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