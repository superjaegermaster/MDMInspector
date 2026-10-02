import Foundation
import SwiftUI

/// Severity of a log record. Mirrors the unified-logging levels plus an explicit
/// `debug` case so nothing is silently dropped (evidence first).
public enum Severity: Int, CaseIterable, Comparable, Hashable {
    case debug = 0
    case info = 1
    case notice = 2
    case warning = 3
    case error = 4
    case fault = 5

    public var label: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .notice: return "Notice"
        case .warning: return "Warning"
        case .error: return "Error"
        case .fault: return "Fault"
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    var color: Color {
        switch self {
        case .debug: return Color(red: 0.55, green: 0.55, blue: 0.58)
        case .info: return Color(red: 0.30, green: 0.55, blue: 0.85)
        case .notice: return Color(red: 0.30, green: 0.65, blue: 0.55)
        case .warning: return Color(red: 0.90, green: 0.68, blue: 0.20)
        case .error: return Color(red: 0.85, green: 0.30, blue: 0.30)
        case .fault: return Color(red: 0.75, green: 0.20, blue: 0.45)
        }
    }

    /// Single-glyph signal used in the timeline.
    var glyph: String {
        switch self {
        case .debug: return "·"
        case .info: return "•"
        case .notice: return "•"
        case .warning: return "!"
        case .error: return "✕"
        case .fault: return "✕"
        }
    }
}

/// Source categories used by the sidebar. Extensible: unknown processes fall
/// back to `.other` so they stay visible rather than being hidden.
public enum SourceCategory: String, CaseIterable, Identifiable, Hashable {
    case all
    case macOS
    case mdm
    case workspaceOne
    case intelligentHub
    case apps
    case network
    case security
    case identity
    case platformSSO
    case intune
    case jamf
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "All"
        case .macOS: return "macOS"
        case .mdm: return "MDM"
        case .workspaceOne: return "Workspace ONE"
        case .intelligentHub: return "Intelligent Hub"
        case .apps: return "Apps"
        case .network: return "Network"
        case .security: return "Security"
        case .identity: return "Identity / SSO"
        case .platformSSO: return "Platform SSO"
        case .intune: return "Microsoft Intune"
        case .jamf: return "Jamf Pro"
        case .other: return "Other"
        }
    }

    /// Sidebar order (the raw-value list includes `.all` first already).
    public static var sidebarOrder: [SourceCategory] { allCases }

    public var color: Color {
        switch self {
        case .all: return Color(red: 0.50, green: 0.50, blue: 0.55)
        case .macOS: return Color(red: 0.25, green: 0.55, blue: 0.90)
        case .mdm: return Color(red: 0.30, green: 0.70, blue: 0.75)
        case .workspaceOne: return Color(red: 0.55, green: 0.35, blue: 0.80)
        case .intelligentHub: return Color(red: 0.30, green: 0.72, blue: 0.45)
        case .apps: return Color(red: 0.35, green: 0.65, blue: 0.80)
        case .network: return Color(red: 0.85, green: 0.60, blue: 0.25)
        case .security: return Color(red: 0.80, green: 0.35, blue: 0.35)
        case .identity: return Color(red: 0.70, green: 0.45, blue: 0.75)
        case .platformSSO: return Color(red: 0.45, green: 0.35, blue: 0.90)
        case .intune: return Color(red: 0.00, green: 0.47, blue: 0.84)
        case .jamf: return Color(red: 0.20, green: 0.60, blue: 0.35)
        case .other: return Color(red: 0.50, green: 0.50, blue: 0.55)
        }
    }

    /// Classify a process by its technical name into EVERY category it belongs
    /// to, not just one.
    ///
    /// A single process can legitimately serve several troubleshooting tracks.
    /// Microsoft Company Portal is the clearest case: it is the Intune agent's
    /// user app *and* the host of the Enterprise SSO extension
    /// (`com.microsoft.CompanyPortalMac.ssoextension`) that brokers Entra ID
    /// authentication for Platform SSO. Forcing it into one bucket would hide it
    /// from exactly the admin who needs it.
    ///
    /// Deliberately data-driven and not exhaustive — the app never hides what
    /// it does not recognise, and unknown processes land in `.other`.
    public static func classifyAll(process: String, message: String = "", subsystem: String = "") -> [SourceCategory] {
        let p = process.lowercased()
        // A separator-free view so "Company Portal", "company_portal" and
        // "companyportal" all match the same rule.
        let flat = p.filter { $0.isLetter || $0.isNumber }
        let sub = subsystem.lowercased()
        let msg = message.lowercased()
        var out: [SourceCategory] = []

        func add(_ c: SourceCategory) { if !out.contains(c) { out.append(c) } }
        func has(_ s: String) -> Bool { p.contains(s) }
        func hasFlat(_ s: String) -> Bool { flat.contains(s) }
        /// The SSO broker itself, whichever vendor, is a Platform SSO record.
        /// Covers Apple's extensible-SSO subsystems and each IdP's own extension
        /// subsystem/process, because Platform SSO failures surface in the
        /// vendor's logging as often as in Apple's.
        func isSSOBroker() -> Bool {
            if sub.hasPrefix("com.apple.appsso") || sub.hasPrefix("com.apple.extensiblesso")
                || sub.hasPrefix("com.apple.heimdal") || sub.hasPrefix("com.apple.ssokit")
                || sub.contains("ssoextension") || sub.contains("macverify") {
                return true
            }
            // Vendor SSO extensions: Microsoft (Company Portal), Okta, Ping, etc.
            if sub.hasPrefix("com.okta.") || sub.hasPrefix("com.microsoft.ssoextension")
                || sub.hasPrefix("com.microsoft.entra") || sub.contains("psso") {
                return true
            }
            return has("ssoextension") || hasFlat("ssoextension")
                || has("appssoagent") || hasFlat("appsso")
                || has("platformsso") || hasFlat("platformsso")
                || has("oktaverify") || hasFlat("oktaverify")
                || has("macverify") || hasFlat("macverify")
        }

        // --- Intune / Company Portal -------------------------------------
        // Intune is matched before the Apple-MDM rule on purpose: agents are
        // named IntuneMDMDaemon / IntuneMDMAgent, which contain "mdm" and would
        // otherwise be swallowed by it.
        let isIntune = has("intune") || hasFlat("intune") || hasFlat("companyportal")
        if isIntune { add(.intune) }

        // --- Enterprise agents -------------------------------------------
        if has("awagent") || has("workspaceone") || has("airwatch") || has("vmware")
            || has("sentinel") || has("oneagent") || has("ws1") {
            add(.intelligentHub)
        }
        if has("mdmclient") || has("profiles") || has("mdm") || has("mobileasset")
            || has("identityservices") || has("authenticatorservices") {
            add(.mdm)
        }

        // --- Platform SSO -------------------------------------------------
        // Company Portal lands here too: the Enterprise SSO extension is hosted
        // inside it, so its registration/authentication records are Platform SSO
        // evidence even though the process is an Intune agent.
        if isSSOBroker() {
            add(.platformSSO)
        } else if isIntune {
            // Only SSO-flavoured records, not every Intune record.
            if msg.contains("sso") || msg.contains("extensible") || msg.contains("associated domain")
                || msg.contains("prt") || msg.contains("kerberos") || msg.contains("entra")
                || msg.contains("credential") || msg.contains("token") || msg.contains("sign-in")
                || msg.contains("sign in") || msg.contains("broker") || msg.contains("registration") {
                add(.platformSSO)
            }
        }

        // --- Other identity ----------------------------------------------
        if has("sso") || has("platformsso") || has("entra")
            || has("aad") || has("microsoft") || has("kerberos") || has("adcert")
            || has("scepman") || has("cmdcertportal") || has("heimdal") {
            add(.identity)
        }
        // Jamf before the generic security rule (Jamf Protect ships a separate
        // endpoint binary that would otherwise land there).
        if has("jamf") || has("jamfd") || has("jamfagent") || has("selfservice") {
            add(.jamf)
        }
        if has("zscaler") || has("tanium") || has("cisco") || has("umbrella")
            || has("crowdstrike") || has("falcon") || has("sentinelone")
            || has("cylance") || has("symantec") || has("carbonblack") || has("defender")
            || has("edr") || has("lulu") || has("firewall") {
            add(.security)
        }
        if has("installer") || has("installd") || has("softwareupdated") || has("softwareupdate")
            || has("managedsoftwareupdate") || has("appstoreagent") {
            add(.apps)
        }
        if has("kernel") || has("launchd") || has("syslogd") || has("logd")
            || has("xpc") || has("securityd") || has("runningboard") || has("lsmd")
            || has("swcd") {
            add(.macOS)
        }
        if has("nsurlsession") || has("network") || has("nw_") || has("configd")
            || has("mdnsresponder") || has("http") || has("proxy")
            || has("wifi") || has("airportd") || has("neagent") || has("nesessionmanager") {
            add(.network)
        }

        // Nothing matched: stay visible as `other` rather than being hidden.
        return out.isEmpty ? [.other] : out
    }

    /// Convenience: the single most specific category, for display where only one
    /// can be shown. Platform SSO and the product bucket are both preserved via
    /// `classifyAll`, so this is only for a one-line label.
    public static func classify(process: String) -> SourceCategory {
        let all = classifyAll(process: process)
        if let sso = all.first(where: { $0 == .platformSSO }) { return sso }
        return all.first ?? .other
    }
}

/// Normalized event model. Independent of the collector that produced it, so
/// additional sources can feed the same UI without changes.
public struct LogEvent: Identifiable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let process: String
    public let executablePath: String
    public let message: String
    public let subsystem: String
    public let category: String
    public let severity: Severity
    /// Every category this event belongs to. An event is usually in exactly one,
    /// but cross-domain records (Company Portal broker activity is both an Intune
    /// and a Platform SSO concern) carry several, so filtering on any of them
    /// finds the record. `source` is the first entry, for single-value display.
    public let sources: [SourceCategory]
    public let eventType: String
    public let rawRecord: String
    /// Which collector produced this record, e.g. "Unified Log", "/var/log/install.log".
    public let collectorID: String

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        process: String,
        executablePath: String,
        message: String,
        subsystem: String,
        category: String,
        severity: Severity,
        source: SourceCategory,
        eventType: String,
        rawRecord: String,
        collectorID: String,
        additionalSources: [SourceCategory] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.process = process
        self.executablePath = executablePath
        self.message = message
        self.subsystem = subsystem
        self.category = category
        self.severity = severity
        self.sources = [source] + additionalSources.filter { $0 != source }
        self.eventType = eventType
        self.rawRecord = rawRecord
        self.collectorID = collectorID
    }

    /// Primary category, used where the UI can show only one.
    public var source: SourceCategory { sources.first ?? .other }

    /// True when the event belongs to the given category (any of them).
    public func matches(_ category: SourceCategory) -> Bool { sources.contains(category) }

    /// "Intune · Platform SSO" for events that span domains.
    public var sourceLabel: String {
        sources.map(\.label).joined(separator: " · ")
    }

    /// Full-text search haystack (message, process, path, subsystem, category).
    public var searchBlob: String {
        var s = message
        s += " " + process
        s += " " + executablePath
        s += " " + subsystem
        s += " " + category
        for c in sources { s += " " + c.label }
        s += " " + collectorID
        return s.lowercased()
    }
}

/// Presentation grouping used by the timeline (§18): process/source based only.
/// No causal claims are made about a group.
public struct EventGroup: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let events: [LogEvent]
}
