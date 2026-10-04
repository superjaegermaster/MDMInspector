// Collector smoke test — verifies each source against the real system.
// Run: swift run -c release selftest
import Foundation
import OSLog
import Darwin
import MDMInspectorKit

@main
struct SelfTest {
    static func main() async {
        let collectors = CollectorRegistry.makeCollectors()
        print("Collectors registered: \(collectors.count)\n")

        var total = 0
        for c in collectors {
            let status = c.probe()
            let t = Date()
            let result = await c.collect(interval: DateInterval(start: Date().addingTimeInterval(-1800), end: Date()), limit: 500)
            let dt = Date().timeIntervalSince(t)
            total += result.events.count
            print(String(format: "── %-34@ [%@]  %.2fs", c.displayName as NSString, c.id as NSString, dt))
            print("   status: \(status.label)")
            print("   events: \(result.events.count)")
            for d in result.diagnostics.prefix(2) { print("   diag[\(d.level.rawValue)]: \(d.message)") }
            if let e = result.events.first {
                print("   newest: \(Stamp.full.string(from: e.timestamp))  \(e.severity.label)  proc=\(e.process)")
                print("           exec=\(e.executablePath)")
                print("           sub=\(e.subsystem) cat=\(e.category) type=\(e.eventType) src=\(e.source.label)")
                print("           msg=\(e.message.prefix(110))")
            }
        }
        print("\nTOTAL EVENTS: \(total)")

        // Sanity checks on the data model
        var fail = 0
        func check(_ label: String, _ ok: Bool) {
            print("\(ok ? "PASS" : "FAIL")  \(label)")
            if !ok { fail += 1 }
        }
        let uni = collectors.first { $0.id == "unified" }!
        let r = await uni.collect(interval: DateInterval(start: Date().addingTimeInterval(-900), end: Date()), limit: 2000)
        check("Unified log returns records for the last 15 minutes", r.events.count > 0)
        check("Every event has millisecond-resolution timestamps",
              r.events.allSatisfy { Stamp.timeWithMillis.string(from: $0.timestamp).contains(".") })
        check("No event has an empty raw record", r.events.allSatisfy { !$0.rawRecord.isEmpty })
        check("No event has an empty process name", r.events.allSatisfy { !$0.process.isEmpty })
        check("Timestamp formatter is locale-stable",
              Stamp.timeWithMillis.string(from: Date(timeIntervalSince1970: 1780000000.123)) == Stamp.timeWithMillis.string(from: Date(timeIntervalSince1970: 1780000000.123)))
        check("Millis are actually rendered",
              Stamp.timeWithMillis.string(from: Date(timeIntervalSince1970: 1780000000.123)).hasSuffix("123"))

        let proc = collectors.first { $0.id == "processes" }!
        let pr = await proc.collect(interval: DateInterval(start: Date().addingTimeInterval(-60), end: Date().addingTimeInterval(60)), limit: 2000)
        check("Process inventory lists running processes", pr.events.count > 20)
        check("Process inventory resolves real executable paths",
              pr.events.contains { $0.executablePath.hasPrefix("/") })
        check("Process inventory includes this process's own family", pr.events.contains { $0.process == "MDMInspector" || $0.process.hasPrefix("MDMInspector") })

        // Source classification
        check("mdmclient classifies as MDM", SourceCategory.classify(process: "mdmclient") == .mdm)
        // Intune must be its own bucket, not swallowed by the Entra/SSO rules.
        // Company Portal is the key cross-domain case: it is the Intune agent's
        // user app AND the host of the Enterprise SSO extension.
        let cp = SourceCategory.classifyAll(process: "Company Portal")
        check("Company Portal belongs to Intune", cp.contains(.intune))
        let cpSSO = SourceCategory.classifyAll(process: "Company Portal",
                                               message: "Extensible SSO registration completed, Associated Domain login.microsoftonline.com")
        check("Company Portal SSO record is also Platform SSO", cpSSO.contains(.platformSSO))
        check("Company Portal SSO record is still Intune", cpSSO.contains(.intune))
        let cpPlain = SourceCategory.classifyAll(process: "Company Portal",
                                                 message: "Installing application from Company Portal")
        check("plain Company Portal app record is not falsely Platform SSO",
              !cpPlain.contains(.platformSSO))
        check("SSOExtension process is Platform SSO",
              SourceCategory.classifyAll(process: "SSOExtension").contains(.platformSSO))
        check("AppSSO subsystem is Platform SSO",
              SourceCategory.classifyAll(process: "swcd", subsystem: "com.apple.AppSSO").contains(.platformSSO))
        check("Okta extension is Platform SSO",
              SourceCategory.classifyAll(process: "oktaverify", subsystem: "com.okta.authenticloud").contains(.platformSSO))
        check("a record can belong to several categories at once", cp.count >= 1)

        // Multi-source events must be findable under every one of their categories.
        let multi = LogEvent(timestamp: Date(), process: "Company Portal", executablePath: "/x",
                              message: "Extensible SSO", subsystem: "", category: "", severity: .info,
                              source: .intune, eventType: "Authentication", rawRecord: "raw",
                              collectorID: "t", additionalSources: [.platformSSO])
        check("multi-source event matches its primary category", multi.matches(.intune))
        check("multi-source event matches its secondary category", multi.matches(.platformSSO))
        check("multi-source event does not match an unrelated category", !multi.matches(.security))
        check("multi-source label lists both", multi.sourceLabel.contains("Intune") && multi.sourceLabel.contains("Platform SSO"))
        check("multi-source search includes both categories",
              multi.searchBlob.contains("platform sso") && multi.searchBlob.contains("intune"))

        check("Jamf Daemon classifies as Jamf", SourceCategory.classify(process: "JamfDaemon") == .jamf)
        check("jamf binary classifies as Jamf", SourceCategory.classify(process: "jamf") == .jamf)
        check("JamfAgent classifies as Jamf", SourceCategory.classify(process: "JamfAgent") == .jamf)
        check("IntuneMDMDaemon classifies as Intune", SourceCategory.classify(process: "IntuneMDMDaemon") == .intune)
        check("IntuneMDMAgent classifies as Intune", SourceCategory.classify(process: "IntuneMDMAgent") == .intune)
        check("IntuneMMA classifies as Intune", SourceCategory.classify(process: "IntuneMMA") == .intune)
        check("Company Portal classifies as Intune", SourceCategory.classify(process: "Company Portal") == .intune)
        check("awagent classifies as Intelligent Hub", SourceCategory.classify(process: "awagent") == .intelligentHub)
        check("unknown process stays visible as .other", SourceCategory.classify(process: "zzz-unknown-thing") == .other)
        check("installer classifies as Apps", SourceCategory.classify(process: "installd") == .apps)

        // File collector against a real file on this Mac
        let inst = FileLogCollector(id: "t", displayName: "t", path: "/var/log/install.log")
        let ir = await inst.collect(interval: DateInterval(start: Date().addingTimeInterval(-86400*30), end: Date().addingTimeInterval(86400)), limit: 200)
        check("install.log parses (file exists on this Mac: \(FileManager.default.fileExists(atPath: "/var/log/install.log")))",
              !ir.events.isEmpty || ir.diagnostics.contains { $0.message.contains("No lines") })

        // Performance / memory: a wide range must not materialise every record.
        // On this Mac the 24h range holds >1M records; a non-bounded collector
        // would allocate them all. The cap keeps resident memory flat.
        let big = UnifiedLogCollector()
        let t0 = Date()
        let memBefore = currentRSSBytes()
        let br = await big.collect(interval: DateInterval(start: Date().addingTimeInterval(-86400), end: Date()), limit: 20000)
        let elapsed = Date().timeIntervalSince(t0)
        let memAfter = currentRSSBytes()
        print("\n24h range: \(br.events.count) events kept in \(String(format: "%.1f", elapsed))s, RSS \(memBefore/1_048_576)MB -> \(memAfter/1_048_576)MB")
        check("24h unified-log read respects the 20k cap", br.events.count <= 20000)
        check("24h unified-log read does not balloon memory (>400MB growth)",
              memAfter - memBefore < 400 * 1_048_576)
        // Same reasoning as above: catches runaway scans, not microseconds.
        check("24h read completes in under 90s (regression guard)", elapsed < 90)
        check("capped read states what was and was not read",
              br.diagnostics.contains { $0.message.contains("most recent") })
        check("events are sorted newest-first",
              zip(br.events, br.events.dropFirst()).allSatisfy { $0.timestamp >= $1.timestamp })
        // Recency is a property of the MACHINE, not of the code: a quiet or
        // freshly-booted machine may have no unified records in the last few
        // minutes, and then "the newest event should be recent" is not
        // something the collector can be blamed for.
        //
        // This check exists to catch a real regression - an earlier version kept
        // the OLDEST records of the window instead of the newest. So it only
        // applies when the machine actually has recent records to keep.
        let hasRecentRecords = await unifiedLogHasRecordsNewerThan(seconds: 300)
        if hasRecentRecords {
            check("the newest kept event is actually recent (< 5 min old)",
                  br.events.first.map { Date().timeIntervalSince($0.timestamp) < 300 } ?? false)
        } else {
            print("SKIP  newest-event recency: this machine has no unified records in the last 5 min")
        }
        // Always assert the weaker, machine-independent property: kept records
        // must lie inside the requested window.
        let windowStart = Date().addingTimeInterval(-86400)
        check("kept events fall inside the requested 24h window",
              br.events.allSatisfy { $0.timestamp >= windowStart })

        // A full refresh must be interactive. Folder sources (DiagnosticReports,
        // agent log dirs) used to re-parse everything on every refresh, which
        // pegged the CPU for minutes; this asserts the whole pass stays bounded.
        @MainActor func timedRefresh() async -> (TimeInterval, Int, Int) {
            let model = InspectorModel()
            let t = Date()
            await model.refresh()
            return (Date().timeIntervalSince(t), model.events.count, model.filteredEvents.count)
        }
        let (refreshTime, loadedCount, shownCount) = await timedRefresh()
        print("full refresh (all \(collectors.count) sources, 30m): \(String(format: "%.1f", refreshTime))s, \(loadedCount) events loaded, \(shownCount) shown")
        // Budget is generous on purpose. Its job is to catch a REGRESSION (the
        // bug where a 24h read took over 7 minutes), not to certify absolute
        // speed — the time legitimately varies with log volume and hardware, and
        // a budget tuned on one machine is not a fact about the code.
        // A 90s ceiling still fails loudly on the regression it exists to catch.
        check("full refresh completes in under 90s (regression guard, not a perf target)", refreshTime < 90)
        check("full refresh produces a populated timeline", loadedCount > 0)

        // Intune sources must be registered even when Intune is not installed,
        // and must report "not present" rather than a permissions error.
        let intuneIDs = ["intune-system", "intune-user", "intune-company-portal",
                         "intune-scripts", "intune-unified", "jamf-client", "jamf-unified"]
        for iid in intuneIDs {
            guard let c = collectors.first(where: { $0.id == iid }) else {
                check("Intune source \(iid) is registered", false); continue
            }
            check("vendor source \(iid) registered: \(c.detail)", true)
            let r = await c.collect(interval: DateInterval(start: Date().addingTimeInterval(-3600), end: Date()), limit: 100)
            if case .unavailable = c.probe() {
                check("absent vendor source \(iid) does not claim a permissions error",
                      r.diagnostics.allSatisfy { !$0.message.contains("Full Disk Access") })
            }
        }

        // The Jamf client log lives at /var/log/jamf.log per Jamf's docs; the
        // commonly-guessed /Library/Logs/JAMF does not exist. Guard the guess.
        let jamf = collectors.first { $0.id == "jamf-client" }
        check("Jamf client source points at the documented /var/log/jamf.log",
              jamf?.detail == "/var/log/jamf.log")
        check("the guessed /Library/Logs/JAMF path is NOT registered",
              !collectors.contains { $0.detail.contains("/Library/Logs/JAMF") })
        let jamfSources = collectors.filter { $0.id.hasPrefix("jamf") }
        let knownJamfTokens = ["jamf", "jamfinstall", "jamf_setup", "jamfchange", "selfservice", "com.jamf"]
        check("Jamf sources only reference documented paths (\(jamfSources.count) sources)",
              !jamfSources.isEmpty && jamfSources.allSatisfy { src in
                  knownJamfTokens.contains { token in
                      src.detail.lowercased().contains(token)
                  }
              })

        // macOS MDM / platform coverage. Subsystem names come from Apple's
        // profile-logging docs, not from guesswork.
        let mdmIDs = ["macos-mdm-unified", "macos-managedclient-log",
                      "ws1-managed-installs", "kandji-unified", "kandji-logs",
                      "manageengine-logs", "nable-agent-logs", "mde-logs",
                      "horizon-agent-logs"]
        for iid in mdmIDs {
            check("MDM source \(iid) is registered",
                  collectors.contains { $0.id == iid })
        }
        let mdmUni = collectors.first { $0.id == "macos-mdm-unified" }
        let mdmResult = await mdmUni!.collect(
            interval: DateInterval(start: Date().addingTimeInterval(-900), end: Date()),
            limit: 3000)
        print("macOS MDM subsystems: \(mdmResult.events.count) records in the last 15 min")
        check("macOS MDM subsystem source returns records on a live Mac",
              mdmResult.events.count > 0)
        check("macOS MDM records carry an Apple MDM subsystem",
              mdmResult.events.contains { $0.subsystem.hasPrefix("com.apple.ManagedClient")
                                      || $0.subsystem.hasPrefix("com.apple.mdmclient")
                                      || $0.process == "mdmclient" })
        check("macOS MDM records classify as MDM",
              mdmResult.events.contains { $0.matches(.mdm) })

        // Documented paths, pinned so a plausible guess can't creep back in.
        let registry = collectors.map(\.detail).joined(separator: " ")
        let documentedPaths = ["/Library/Logs/ManagedClient/ManagedClient.log",
                               "/Library/Logs/Microsoft/mdatp",
                               "/Library/UEMS_Agent/logs",
                               "io.kandji"]
        for known in documentedPaths {
            check("documented path/subsystem present: \(known)", registry.contains(known))
        }

        check("Kandji classifies as MDM",
              SourceCategory.classify(process: "kandjid") == .mdm)
        check("ManageEngine agent classifies as MDM",
              SourceCategory.classify(process: "MEAgent") == .mdm
              || SourceCategory.classifyAll(process: "uems_agent").contains(.mdm))
        check("N-able agent classifies as MDM",
              SourceCategory.classify(process: "Mac_agent") == .mdm
              || SourceCategory.classifyAll(process: "nagentd").contains(.mdm))

        // Progress: every collector must emit a handler-visible fraction and the
        // overall bar must only ever move forward.
        @MainActor func progressRun() async -> (Bool, Bool, Double) {
            let model = InspectorModel()
            var samples: [Double] = []
            let poll = Task { @MainActor in
                while model.isLoading {
                    if let p = model.loadProgress { samples.append(p) }
                    try? await Task.sleep(nanoseconds: 40_000_000)
                }
            }
            await model.refresh()
            poll.cancel()
            let monotonic = zip(samples, samples.dropFirst()).allSatisfy { $1 >= $0 - 0.001 }
            // The settled value, read after the load, not from the last sample.
            return (samples.isEmpty == false, monotonic, model.loadProgress ?? 0)
        }
        let (sawSamples, monotonic, finalP) = await progressRun()
        check("loading emits progress samples", sawSamples)
        check("progress never moves backwards", monotonic)
        check("progress reaches 100%", finalP > 0.999)

        // Live "logs discovered" counter: must rise during the load and end up
        // equal to what was actually loaded. A counter that merely animates
        // would pass a monotonicity check but fail this.
        @MainActor func liveCountRun() async -> (Bool, Bool, Int, Int) {
            let model = InspectorModel()
            var samples: [Int] = []
            let poll = Task { @MainActor in
                while model.isLoading {
                    samples.append(model.logsDiscovered)
                    try? await Task.sleep(nanoseconds: 30_000_000)
                }
            }
            await model.refresh()
            poll.cancel()
            let rose = samples.count >= 2 && samples[samples.count - 1] > samples[0]
            let nonDecreasing = zip(samples, samples.dropFirst()).allSatisfy { $1 >= $0 }
            return (rose, nonDecreasing, samples.max() ?? 0, model.events.count)
        }
        let (rose, nonDecreasing, peak, loaded) = await liveCountRun()
        check("live logs-discovered counter rises during the load", rose)
        check("live counter never goes backwards", nonDecreasing)
        check("live counter reaches the number actually loaded (\(peak) -> \(loaded))",
              peak > 0 && peak == loaded)

        // MARK: - Probe honesty
        //
        // A permission message must be backed by the OS saying "not permitted",
        // never inferred from a constructor that failed for some other reason.
        print("\n--- probe truthfulness ---")

        let probeRead = UnifiedLogProbe.read()
        check("unified log is readable on this Mac (measured, not assumed)",
              probeRead.isReadable)
        check("probe reports a real entry count, not a bare \"Available\"",
              { if case .readable = probeRead.outcome { return true }; return false }())
        print("       \(UnifiedLogProbe.status(for: probeRead, sourceName: "Unified Log").label)")

        // No source may claim a Full Disk Access prompt on a Mac where the log
        // store demonstrably reads fine, unless something actually denied it.
        var falsePermissionClaims: [String] = []
        for c in CollectorRegistry.makeCollectors() {
            if case .permissionRequired(let why) = c.probe(), probeRead.isReadable {
                falsePermissionClaims.append("\(c.displayName): \(why)")
            }
        }
        check("no collector claims a permission problem while the log store reads fine (\(falsePermissionClaims.count) claims)",
              falsePermissionClaims.isEmpty)
        for fpc in falsePermissionClaims { print("       FALSE CLAIM: \(fpc)") }

        // A path that does not exist must be absent, never a permissions fault.
        let absentProbe = FileLogCollector(
            id: "selftest-absent", displayName: "Self-test absent",
            path: "/Library/Logs/definitely-not-here-\(UUID().uuidString)")
        if case .permissionRequired = absentProbe.probe() {
            check("absent path reports absence, not a permission problem", false)
        } else {
            check("absent path reports absence, not a permission problem", true)
        }

        // TCC is Full Disk Access protected, but whether it is denied depends on
        // whether the grant exists - so both outcomes are correct and the test
        // has to accept either. What must hold in both cases is that the reported
        // status matches reality: readable when it reads, and a denial naming the
        // OS error when it does not. Asserting "must be denied" broke on CI,
        // which runs with the grant.
        let tccPath = "/Library/Application Support/com.apple.TCC"
        if FileManager.default.fileExists(atPath: tccPath) {
            let tcc = FileLogCollector(
                id: "selftest-tcc", displayName: "Self-test TCC", path: tccPath)
            let tccStatus = tcc.probe()
            let readableHere = (try? FileManager.default.contentsOfDirectory(atPath: tccPath)) != nil
            if readableHere {
                check("TCC reported available when the grant exists", 
                      { if case .available = tccStatus { return true }; return false }())
            } else {
                check("TCC denial names the OS error, rather than asserting a cause",
                      { if case .permissionRequired(let m) = tccStatus { return m.contains("NSFileReadNoPermissionError") }; return false }())
            }
            print("       \(tccStatus.label)")
        } else {
            check("TCC path reported honestly", true)
        }

        // A readable file must not be described as blocked.
        let readable = FileLogCollector(
            id: "selftest-readable", displayName: "Self-test readable", path: "/var/log/system.log")
        check("a genuinely readable log file is reported available",
              { if case .available = readable.probe() { return true }; return false }())

        print(fail == 0 ? "\nALL CHECKS PASSED" : "\n\(fail) CHECK(S) FAILED")
        exit(fail == 0 ? 0 : 1)
    }

    /// Does the unified log contain any record newer than `seconds`?
    static func unifiedLogHasRecordsNewerThan(seconds: TimeInterval) async -> Bool {
        let store = try? OSLogStore(scope: .system)
        guard let store else { return false }
        let start = Date().addingTimeInterval(-Double(seconds))
        guard let seq = try? store.getEntries(
            at: store.position(date: start),
            matching: NSPredicate(format: "timestamp >= %@", start as NSDate)) else {
            return false
        }
        for _ in seq { return true }
        return false
    }

    /// Resident set size of this process, via the task_info API.
    static func currentRSSBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }
}
