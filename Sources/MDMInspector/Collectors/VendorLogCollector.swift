import Foundation
import OSLog

/// Unified-log view filtered to one vendor's subsystems and processes.
///
/// Intune and Jamf both write to the Unified Log as well as to their own files
/// (Jamf's docs point at `subsystem BEGINSWITH "com.jamf.management.daemon"`),
/// so filtering the store surfaces records a plain file read cannot reach.
///
/// Two measured facts shape the design (measured on this Mac, 5-minute window):
///   * `subsystem` is an indexed key — a filtered query returns in ~0.1s.
///   * `process` is NOT indexed — the same query shape took ~3.4s.
/// So we query `subsystem` first and only fall back to the slow `process` scan
/// if that came back empty.
final class VendorLogCollector: LogCollector {
    let id: String
    let displayName: String
    let detail: String

    private let subsystemPrefixes: [String]
    private let processNames: [String]
    private let source: SourceCategory
    private let maxRecords: Int

    init(id: String,
         displayName: String,
         detail: String,
         subsystemPrefixes: [String],
         processNames: [String],
         source: SourceCategory,
         maxRecords: Int = 5000) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.subsystemPrefixes = subsystemPrefixes
        self.processNames = processNames
        self.source = source
        self.maxRecords = maxRecords
    }

    private lazy var subsystemClauses: [NSPredicate] =
        subsystemPrefixes.map { NSPredicate(format: "subsystem BEGINSWITH %@", $0) }

    private lazy var processClauses: [NSPredicate] =
        processNames.map { NSPredicate(format: "process == %@", $0) }

    func probe() -> CapabilityStatus {
        // Shared with the generic unified-log collector so every source reports
        // the same measured truth rather than each guessing from a constructor.
        UnifiedLogProbe.status(for: UnifiedLogProbe.readCached(), sourceName: displayName)
    }

    func collect(interval: DateInterval, limit: Int) async -> CollectResult {
        await collect(interval: interval, limit: limit, progress: { _ in })
    }

    func collect(interval: DateInterval, limit: Int,
                 progress: @escaping ProgressHandler) async -> CollectResult {
        var result = CollectResult()
        progress(LoadProgress(fraction: 0.05, stage: "Opening unified log"))

        guard !subsystemClauses.isEmpty || !processClauses.isEmpty else { return result }

        let store: OSLogStore
        do {
            store = try OSLogStore(scope: .system)
        } catch {
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .error,
                message: "Cannot open the system-wide unified log: \(error.localizedDescription)"))
            return result
        }

        let cap = min(limit, maxRecords)

        // Cheap precheck. If none of this vendor's processes are running, a full
        // range scan can only return records from an agent that has since exited,
        // so search a short recent window instead - the difference between a
        // fast source and a multi-second one on a Mac where it isn't installed.
        let runningNames = Set(ProcessPathResolver.allProcesses().map(\.name))
        let anyRunning = processNames.contains { runningNames.contains($0) }
        let probeSeconds: TimeInterval = anyRunning ? interval.duration : min(interval.duration, 300)
        let windowStart = max(interval.start, interval.end.addingTimeInterval(-probeSeconds))

        progress(LoadProgress(fraction: 0.15, stage: "Scanning \(displayName) records"))

        /// Chunked backwards scan over [windowStart, end], stopping at `cap`.
        func scan(_ vendorPredicate: NSPredicate) throws -> [OSLogEntry] {
            let chunk = max(15, min(probeSeconds, 300))
            let totalChunks = max(1, Int(ceil(probeSeconds / chunk)))
            var out: [OSLogEntry] = []
            var cursor = interval.end
            var n = 0
            while out.count < cap && cursor > windowStart {
                let chunkStart = max(windowStart, cursor - chunk)
                let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    vendorPredicate,
                    NSPredicate(format: "timestamp >= %@", chunkStart as NSDate),
                    NSPredicate(format: "timestamp <= %@", cursor as NSDate)
                ])
                let seq = try store.getEntries(at: store.position(date: chunkStart), matching: pred)
                for e in seq {
                    out.append(e)
                    if out.count >= cap { break }
                }
                n += 1
                cursor = chunkStart
                let fraction = out.count >= cap
                    ? 1.0
                    : min(0.9, 0.15 + 0.7 * Double(n) / Double(totalChunks))
                progress(LoadProgress(fraction: fraction,
                                      stage: "\(displayName): \(out.count.formatted()) records",
                                      recordsSoFar: out.count))
                if cursor <= windowStart { break }
            }
            return out
        }

        var kept: [OSLogEntry] = []
        var usedSlowProcessPass = false
        do {
            if !subsystemClauses.isEmpty {
                kept = try scan(NSCompoundPredicate(orPredicateWithSubpredicates: subsystemClauses))
            }
            // Only pay for the un-indexed process scan when the fast pass is empty.
            if kept.isEmpty && !processClauses.isEmpty {
                usedSlowProcessPass = true
                kept = try scan(NSCompoundPredicate(orPredicateWithSubpredicates: processClauses))
            }
        } catch {
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .error,
                message: "Read failed: \(error.localizedDescription)"))
            return result
        }

        if kept.isEmpty {
            var msg = "No \(displayName) records in the selected range. This is normal when \(displayName) is not installed on this Mac."
            if !anyRunning {
                msg = "No \(displayName) records, and none of its processes (\(processNames.prefix(3).joined(separator: ", "))) are running - \(displayName) does not appear to be installed here. Only the last \(max(1, Int(probeSeconds / 60))) min were searched."
            }
            result.diagnostics.append(DiagnosticEvent(collector: displayName, level: .info, message: msg))
            return result
        }

        if !anyRunning && probeSeconds < interval.duration {
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .warning,
                message: "\(displayName) processes are not running, so only the last \(max(1, Int(probeSeconds / 60))) min were searched (the full range is \(max(1, Int(interval.duration / 60))) min)."))
        }
        if usedSlowProcessPass {
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .info,
                message: "Matched by process name - the log store does not index 'process', so this source is slower than the unified-wide read."))
        }

        let paths = ProcessPathResolver.pathMap()
        result.events = kept.map { normalize($0, paths: paths) }.sorted { $0.timestamp > $1.timestamp }
        progress(LoadProgress(fraction: 1, stage: "Done", recordsSoFar: result.events.count))
        return result
    }

    private func normalize(_ entry: OSLogEntry, paths: [String: String]) -> LogEvent {
        var process = "-"
        var subsystem = ""
        var category = ""
        var severity: Severity = .info
        if let l = entry as? OSLogEntryLog {
            process = l.process
            subsystem = l.subsystem
            category = l.category
            severity = Severity(osLogLevel: l.level)
        } else if let a = entry as? OSLogEntryActivity {
            process = a.process
        }
        let message = entry.composedMessage
        // Union of the vendor's own bucket with whatever the process/subsystem
        // says it is, so a Platform SSO record from an Intune agent is findable
        // under both.
        var all = SourceCategory.classifyAll(process: process, message: message, subsystem: subsystem)
        if !all.contains(source) { all.insert(source, at: 0) }
        return LogEvent(
            timestamp: entry.date,
            process: process,
            executablePath: paths[process] ?? "-",
            message: message,
            subsystem: subsystem,
            category: category,
            severity: severity,
            source: all.first ?? source,
            eventType: classifyEventType(message: message, level: severity),
            rawRecord: "\(Stamp.full.string(from: entry.date))  \(subsystem)  \(category)  \(process)  - \(message)",
            collectorID: id,
            additionalSources: Array(all.dropFirst())
        )
    }
}
