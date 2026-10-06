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
            // The current Omnissa macOS page lists Managed Installs as the
            // local Hub/Munki evidence surface. Linux's /var/log/ws1-hub path
            // is deliberately not registered for a Mac build.
            ("ws1-data-logs", "Intelligent Hub Data Logs", "/Library/Application Support/AirWatch/Data/Logs"),
            ("ws1-managedsoftwareupdate", "ManagedSoftwareUpdate.log", "/Library/Application Support/AirWatch/Data/Munki/managed installs/logs/ManagedSoftwareUpdate.log"),
            ("ws1-installinfo", "WS1 InstallInfo", "/Library/Application Support/AirWatch/Data/Munki/Managed Installs/InstallInfo.plist"),
            ("ws1-installreport", "WS1 Managed Install Report", "/Library/Application Support/AirWatch/Data/Munki/Managed Installs/ManagedInstallReport.plist"),
            ("ws1-appstatuses", "WS1 App Statuses", "/Library/Application Support/AirWatch/Data/AppStatuses_WS1.plist"),
            ("ws1-agent", "Intelligent Hub (legacy agent log)", "/var/log/VMwareAirWatchAgent.log"),
            ("ws1-agent-alt", "Intelligent Hub (legacy path)", "/Library/Logs/VMwareAirWatchAgent/agent.log"),
            ("ws1-agent-log-dir", "Intelligent Hub (legacy log dir)", "/Library/Logs/VMwareAirWatchAgent"),
            ("ws1-services", "Hub Services (legacy path)", "/Library/Logs/AirWatch"),
            ("ws1-support", "Intelligent Hub (legacy support path)", "/Library/Application Support/AirWatchAgent"),
            ("ws1-workflow", "Workspace ONE Workflows", "/Library/Logs/Workflow"),
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
        collectors.append(VendorLogCollector(
            id: "ws1-unified",
            displayName: "Workspace ONE Intelligent Hub (Unified Log)",
            detail: "Hub and macOS management activity from hubd, awagent, mdmclient and AirWatch subsystems",
            subsystemPrefixes: ["com.air-watch", "com.airwatch", "com.vmware.airwatch", "com.omnissa"],
            processNames: ["hubd", "awagent", "AWProcessCommands", "mdmclient", "awcmclient", "ws1HubUtil"],
            source: .intelligentHub
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

        // --- macOS MDM & platform --------------------------------------
        // The subsystems an Apple admin actually greps for when a profile or
        // an MDM command misbehaves. Until now these were only reachable through
        // the catch-all unified source, mixed in with everything else.
        collectors.append(VendorLogCollector(
            id: "macos-mdm-unified",
            displayName: "macOS MDM & Platform (Unified Log)",
            detail: "Profile installation, MDM commands, app install coordination, software update and Gatekeeper: com.apple.ManagedClient, mdmclient, installcoordination, mobileasset, SoftwareUpdate, amfi",
            subsystemPrefixes: ["com.apple.ManagedClient", "com.apple.mdmclient",
                               "com.apple.installcoordination", "com.apple.mobileasset",
                               "com.apple.mac.install", "com.apple.SoftwareUpdate",
                               "com.apple.amfi"],
            processNames: ["mdmclient", "profiles", "installd", "softwareupdated",
                           "mobileassetd", "AMASManager", "assetd", "nsurlsessiond"],
            source: .mdm
        ))
        // Apple's own profile-install log. Not part of unified logging; parts
        // of ManagedClient still write here (Apple's profile docs).
        collectors.append(FileLogCollector(
            id: "macos-managedclient-log",
            displayName: "ManagedClient Profile Log",
            path: "/Library/Logs/ManagedClient/ManagedClient.log"))
        // Workspace ONE software distribution (managed installs), documented by
        // Omnissa in the macOS management troubleshooting guide.
        collectors.append(FileLogCollector(
            id: "ws1-managed-installs",
            displayName: "WS1 Managed Installs (Munki)",
            path: "/Library/Application Support/AirWatch/Data/Munki/Managed Installs/Logs"))

        // --- Other MDM vendors ------------------------------------------
        // Paths below are taken from each vendor's own documentation.
        collectors.append(VendorLogCollector(
            id: "kandji-unified",
            displayName: "Kandji (Unified Log)",
            detail: "Kandji agent: subsystem io.kandji.* (Kandji docs)",
            subsystemPrefixes: ["io.kandji"],
            processNames: ["kandji", "kandjid", "KandjiAgent"],
            source: .mdm
        ))
        collectors.append(FileLogCollector(
            id: "kandji-logs",
            displayName: "Kandji",
            path: "/Library/Logs/Kandji"))
        collectors.append(FileLogCollector(
            id: "manageengine-logs",
            displayName: "ManageEngine",
            path: "/Library/UEMS_Agent/logs"))
        collectors.append(FileLogCollector(
            id: "nable-agent-logs",
            displayName: "N-able Agent",
            path: "/Library/Logs/N-central Agent"))
        collectors.append(FileLogCollector(
            id: "nable-nagent",
            displayName: "N-able N-agent",
            path: "/var/log/N-able/N-agent"))
        collectors.append(FileLogCollector(
            id: "horizon-agent-logs",
            displayName: "Omnissa Horizon Agent",
            path: "/var/log/omnissa"))
        collectors.append(FileLogCollector(
            id: "horizon-client-logs",
            displayName: "Omnissa Horizon Client",
            path: NSString(string: "~/Library/Logs/Omnissa").expandingTildeInPath))
        // Microsoft Defender for Endpoint on macOS: mdatp logs, including
        // install.log and microsoft-defender_core.log.
        collectors.append(FileLogCollector(
            id: "mde-logs",
            displayName: "Microsoft Defender for Endpoint",
            path: "/Library/Logs/Microsoft/mdatp"))

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
