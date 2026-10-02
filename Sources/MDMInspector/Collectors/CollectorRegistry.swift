import Foundation

/// The source/plugin registry. Adding a source here is all that is required to
/// make it discoverable, filterable and listed in the Capabilities center.
public enum CollectorRegistry {
    public static func makeCollectors() -> [any LogCollector] {
        var collectors: [any LogCollector] = [UnifiedLogCollector(), ProcessInventoryCollector()]

        let fileSources: [(id: String, name: String, path: String)] = [
            // Apple / macOS
            ("install-log", "Install Log", "/var/log/install.log"),
            ("install-log-0", "Install Log (rotated)", "/var/log/install.log.0"),
            ("system-log", "System Log", "/var/log/system.log"),
            ("appfirewall", "Application Firewall", "/var/log/appfirewall.log"),
            ("wifi-log", "Wi-Fi Log", "/var/log/wifi.log"),
            ("daily-out", "Daily Log", "/var/log/daily.out"),
            ("asl", "Apple System Log", "/var/log/asl"),
            ("diagnostics-reports", "Crash & Diagnostic Reports", "/Library/Logs/DiagnosticReports"),
            // Workspace ONE / Intelligent Hub — local evidence only
            ("ws1-agent", "Intelligent Hub (agent log)", "/var/log/VMwareAirWatchAgent.log"),
            ("ws1-agent-alt", "Intelligent Hub (alt path)", "/Library/Logs/VMwareAirWatchAgent/agent.log"),
            ("ws1-agent-log-dir", "Intelligent Hub (log dir)", "/Library/Logs/VMwareAirWatchAgent"),
            ("ws1-services", "Hub Services", "/Library/Logs/AirWatch"),
            ("ws1-support", "Intelligent Hub (support)", "/Library/Application Support/AirWatchAgent"),
            // Microsoft Intune — Management Extension (IME).
            // System-level agent logs, the paths Microsoft itself documents for
            // the Intune log-collection remote action.
            ("intune-system", "Intune Agent (system)", "/Library/Logs/Microsoft/Intune"),
            // User-level agent logs (per-user, hidden ~/Library).
            ("intune-user", "Intune Agent (user)", NSString(string: "~/Library/Logs/Microsoft/Intune").expandingTildeInPath),
            // Company Portal. The user-context app log is
            // ~/Library/Logs/CompanyPortal.log; the installCompanyPortal script
            // writes into the IntuneScripts tree (see Microsoft shell-intune-samples).
            ("intune-company-portal", "Company Portal", NSString(string: "~/Library/Logs/CompanyPortal.log").expandingTildeInPath),
            // Shell scripts and app deployments deployed via Intune log here,
            // one folder per script name.
            ("intune-scripts", "Intune Scripts & App Deploy", "/Library/Logs/Microsoft/IntuneScripts"),
            ("intune-scripts-install-cp", "Intune: Company Portal Install", "/Library/Logs/Microsoft/IntuneScripts/installCompanyPortal"),
            // Autoupdate / Office telemetry: adjacent Microsoft activity that
            // shows up alongside Intune on managed Macs.
            ("ms-autoupdate", "Microsoft AutoUpdate", "/Library/Logs/Microsoft/autoupdate.log"),
            ("ms-installlogs", "Microsoft Installer Logs", "/Library/Logs/Microsoft/InstallLogs"),
            // Enterprise agents
            ("msi", "MSI Installer", "/var/log/msi"),
            ("adobe", "Adobe", "/Library/Logs/Adobe"),
            // Jamf — client-side paths from Jamf's "Components Installed on
            // Managed Computers" documentation. Note the client log is
            // /var/log/jamf.log, NOT /Library/Logs/JAMF (which does not exist).
            ("jamf-client", "Jamf Client Log", "/var/log/jamf.log"),
            ("jamf-install", "Jamf Install Log", "/var/log/jamfinstall.log"),
            ("jamf-setup", "Jamf Setup Log", "/var/log/jamf_setup.log"),
            ("jamf-change", "Jamf Change Management", "/var/log/JAMFChangeManagement.log"),
            ("jamf-bin-dir", "Jamf Binary Logs", "/usr/local/jamf/bin"),
            ("jamf-selfservice", "Jamf Self Service", "/var/log/selfservice"),
            ("zscaler", "Zscaler", "/Library/Application Support/Zscaler"),
            ("sccm", "Configuration Manager Client", "/Library/Logs/Configuration Manager"),
            ("cisco", "Cisco Software", "/Library/Logs/Cisco")
        ]
        for s in fileSources {
            collectors.append(FileLogCollector(id: s.id, displayName: s.name, path: s.path))
        }

        // Vendor views over the unified log, filtered by subsystem/process.
        // Subsystems and process names come from vendor documentation, not
        // guesswork:
        //  - Jamf: "subsystem BEGINSWITH com.jamf.management.daemon" (Jamf docs,
        //    Components Installed on Managed Computers).
        //  - Intune: agent processes IntuneMDMDaemon / IntuneMDMAgent /
        //    IntuneMMA (Intune docs, macOS app-deployment troubleshooting).
        collectors.append(VendorLogCollector(
            id: "jamf-unified",
            displayName: "Jamf (Unified Log)",
            detail: "Unified-log records with subsystem com.jamf.*, and jamf/JamfDaemon/JamfAgent processes",
            subsystemPrefixes: ["com.jamf"],
            processNames: ["jamf", "jamfd", "JamfAgent", "JamfDaemon", "JAMFChangeManagement", "Self Service"],
            source: .jamf
        ))
        collectors.append(VendorLogCollector(
            id: "intune-unified",
            displayName: "Intune (Unified Log)",
            detail: "Unified-log records from IntuneMDMDaemon / IntuneMDMAgent / IntuneMMA and Company Portal",
            subsystemPrefixes: ["com.microsoft.intune", "com.microsoft.enterprise"],
            processNames: ["IntuneMDMDaemon", "IntuneMDMAgent", "IntuneMMA",
                          "IntuneMdmAgent", "IntuneMdmDaemon", "Company Portal", "CompanyPortal"],
            source: .intune
        ))
        // --- Platform SSO -------------------------------------------------
        // macOS Platform SSO is the Apple extensible-SSO framework brokered by
        // whichever IdP's SSO extension is installed. Apple's own subsystems plus
        // each vendor's extension cover both the "with other MDMs" and the
        // Entra/Company Portal cases.
        collectors.append(VendorLogCollector(
            id: "platformsso-unified",
            displayName: "Platform SSO (Unified Log)",
            detail: "macOS extensible SSO: subsystems com.apple.AppSSO / com.apple.extensiblesso, plus vendor SSO extensions (Microsoft, Okta, Jamf)",
            subsystemPrefixes: ["com.apple.AppSSO", "com.apple.extensiblesso",
                               "com.apple.heimdal", "com.apple.ssokit",
                               "com.microsoft.ssoextension", "com.microsoft.entra",
                               "com.okta.authenticloud", "com.jamf.sso"],
            processNames: ["SSOExtension", "AppSSOAgent", "KerberosExtension",
                          "KerberosMenuExtra", "swcd", "app-sso"],
            source: .platformSSO
        ))
        // Company Portal ships the Microsoft Enterprise SSO extension inside its
        // sandbox; Microsoft documents tailing this directory for SSOExtension.log.
        collectors.append(FileLogCollector(
            id: "platformsso-ms-ssoext",
            displayName: "Microsoft SSO Extension Log",
            path: NSString(string: "~/Library/Containers/com.microsoft.CompanyPortalMac.ssoextension/Data/Library/Caches/Logs/Microsoft/SSOExtension").expandingTildeInPath,
            detail: "SSOExtension.log written by the Microsoft Enterprise SSO extension inside Company Portal (Microsoft troubleshooting guide)"))
        collectors.append(FileLogCollector(
            id: "platformsso-ms-container",
            displayName: "Microsoft SSO Container Logs",
            path: NSString(string: "~/Library/Containers/com.microsoft.CompanyPortalMac.ssoextension/Data/Library/Logs").expandingTildeInPath))
        // Other vendors' SSO extension logs, for the "Platform SSO with other
        // MDMs" case. Present only if that product is installed.
        collectors.append(FileLogCollector(
            id: "platformsso-okta",
            displayName: "Okta Verify Logs",
            path: NSString(string: "~/Library/Group Containers/B7F62B65BN.group.okta.macverify.shared/Logs").expandingTildeInPath,
            detail: "Okta Verify / PSSO extension logs (shared group container)"))
        collectors.append(FileLogCollector(
            id: "platformsso-kerberos",
            displayName: "Kerberos (Heimdal)",
            path: "/var/log/krb5-services.log"))

        return collectors
    }
}

/// Reports the currently running processes with their executable paths. This is
/// a genuine local source (§6 automatic process discovery) and it keeps working
/// even where log reading is restricted.
public final class ProcessInventoryCollector: LogCollector {
    public let id = "processes"
    public let displayName = "Running Processes"
    public let detail = "Live process inventory of this Mac (name + executable path)"

    public func probe() -> CapabilityStatus { .available("Available") }

    public func collect(interval: DateInterval, limit: Int) async -> CollectResult {
        await collect(interval: interval, limit: limit, progress: { _ in })
    }

    public func collect(interval: DateInterval, limit: Int,
                        progress: @escaping ProgressHandler) async -> CollectResult {
        var result = CollectResult()
        progress(LoadProgress(fraction: 0.3, stage: "Reading process list"))
        let now = Date()
        let processes = ProcessPathResolver.allProcesses()
        var events: [LogEvent] = []
        events.reserveCapacity(min(processes.count, limit))

        for (name, path, pid) in processes {
            let all = SourceCategory.classifyAll(process: name)
            if events.count % 200 == 0 {
                progress(LoadProgress(fraction: 0.3 + 0.6 * Double(events.count) / Double(max(1, limit)),
                                      stage: "Reading process list",
                                      recordsSoFar: events.count))
            }
            events.append(LogEvent(
                timestamp: now,
                process: name,
                executablePath: path,
                message: "Process running (pid \(pid))",
                subsystem: "com.apple.kernel",
                category: "Process Inventory",
                severity: .info,
                source: all.first ?? .other,
                eventType: "Process",
                rawRecord: "pid=\(pid)  \(path)",
                collectorID: id,
                additionalSources: Array(all.dropFirst())
            ))
            if events.count >= limit { break }
        }
        progress(LoadProgress(fraction: 1, stage: "Done", recordsSoFar: events.count))
        result.events = events
        result.diagnostics.append(DiagnosticEvent(
            collector: displayName, level: .info,
            message: "Snapshot of \(events.count.formatted()) running processes at \(Stamp.full.string(from: now))."))
        return result
    }
}
