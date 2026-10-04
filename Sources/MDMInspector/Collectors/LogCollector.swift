import Foundation
import OSLog

/// Source/collector abstraction (§32). Collectors normalize their records into
/// `LogEvent`; the UI never changes when a collector is added.
public protocol LogCollector: AnyObject, Identifiable {
    var id: String { get }
    var displayName: String { get }
    /// Human-readable description of where the records come from.
    var detail: String { get }
    /// Availability of this source on the current Mac (§27).
    func probe() -> CapabilityStatus
    /// Fetch existing records for the interval. Non-throwing contract: failures
    /// are surfaced through `DiagnosticEvent`s, never hidden.
    func collect(interval: DateInterval, limit: Int,
                 progress: @escaping ProgressHandler) async -> CollectResult

    /// Default for callers that do not care about progress (tests, probes).
    func collect(interval: DateInterval, limit: Int) async -> CollectResult
}

public struct CollectResult {
    public var events: [LogEvent] = []
    public var diagnostics: [DiagnosticEvent] = []
}

/// Progress reported while a collector reads, so the UI can show a real bar
/// instead of an indeterminate spinner. Fractions are per-collector.
public struct LoadProgress: Equatable {
    /// 0...1 for this collector, or nil when it cannot predict.
    public var fraction: Double?
    public var stage: String
    /// 0...1 across the whole refresh, filled in by the model.
    public var overall: Double = 0
    /// Records this collector has produced SO FAR, as it streams them.
    /// The model sums these into the live "logs discovered" readout, so the
    /// number is a real count of records found — never a synthetic animation.
    public var recordsSoFar: Int = 0
}

/// Passed into `collect` so long-running reads can report progress.
public typealias ProgressHandler = @Sendable (LoadProgress) -> Void

public struct DiagnosticEvent: Identifiable, Hashable {
    public enum Level: String { case info, warning, error }
    public let id = UUID()
    public let collector: String
    public let level: Level
    public let message: String
}

public enum CapabilityStatus: Equatable {
    case available(String)
    case permissionRequired(String)
    case unavailable(String)

    public var label: String {
        switch self {
        case .available(let s): return s
        case .permissionRequired(let s): return s
        case .unavailable(let s): return s
        }
    }

    public var isAvailable: Bool { if case .available = self { return true }; return false }
}

// MARK: - Unified Log (Apple / macOS)

/// MVP-2: real local Unified Logging via OSLogStore.
public final class UnifiedLogCollector: LogCollector {
    public let id = "unified"
    public let displayName = "Unified Log"
    public let detail = "Apple Unified Logging (OSLogStore) — all processes on this Mac"

    private let maxRecords: Int

    public init(maxRecords: Int = 20000) { self.maxRecords = maxRecords }

    public func probe() -> CapabilityStatus {
        // Reads a short window for real instead of inferring readability from
        // whether the store could be constructed. Creating an OSLogStore does not
        // read anything, and on a Mac with no Full Disk Access grant the store
        // opens and returns hundreds of thousands of entries - so the old check
        // both over- and under-reported.
        UnifiedLogProbe.status(for: UnifiedLogProbe.readCached(), sourceName: displayName)
    }

    public func collect(interval: DateInterval, limit: Int) async -> CollectResult {
        await collect(interval: interval, limit: limit, progress: { _ in })
    }

    public func collect(interval: DateInterval, limit: Int,
                        progress: @escaping ProgressHandler) async -> CollectResult {
        var result = CollectResult()
        progress(LoadProgress(fraction: 0, stage: "Opening unified log store"))

        let store: OSLogStore
        do {
            store = try OSLogStore(scope: .system)
        } catch {
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .error,
                message: "Cannot open the system-wide unified log: \(error.localizedDescription). See the Capabilities tab for the remediation path."))
            return result
        }

        let cap = min(limit, maxRecords)
        progress(LoadProgress(fraction: 0.02, stage: "Reading records"))

        // Performance notes (this is the hot path):
        //
        // * OSLogStore iterates oldest-first and has no reverse cursor, so the
        //   newest records can only be reached by scanning.
        // * A busy Mac holds >1M records in 24h, so scanning the whole range to
        //   keep the newest `cap` is far too slow (minutes, pegging the CPU).
        //
        // We therefore walk the range backwards in fixed, NON-OVERLAPPING
        // chunks, newest chunk first, keeping the newest `cap` records seen so
        // far in a ring buffer, and stop the moment the cap is reached. Total
        // work is proportional to what we actually consume rather than to the
        // size of the selected range, and nothing is ever read twice.
        // Chunks are walked newest-first, so the first records we keep ARE the
        // newest of the range. Later (older) chunks only ever fill remaining
        // slots — they must never evict a newer record, so this is a plain
        // append with an early stop, not an evicting ring.
        var kept: [OSLogEntry] = []
        kept.reserveCapacity(cap)
        var cursor = interval.end
        var chunksRead = 0
        var firstChunkStart = cursor
        let chunk = max(15, min(interval.duration, 300))   //<=5 min per scan
        let totalChunks = max(1, Int(ceil(interval.duration / chunk)))

        while kept.count < cap && cursor > interval.start {
            let chunkStart = max(interval.start, cursor - chunk)
            firstChunkStart = chunkStart
            do {
                let seq = try store.getEntries(
                    at: store.position(date: chunkStart),
                    matching: NSPredicate(format: "timestamp >= %@ AND timestamp <= %@",
                                          chunkStart as NSDate, cursor as NSDate))
                // Entries arrive oldest-first within the chunk.
                for e in seq {
                    kept.append(e)
                    if kept.count >= cap { break }
                }
            } catch {
                result.diagnostics.append(DiagnosticEvent(
                    collector: displayName, level: .error,
                    message: "Read failed: \(error.localizedDescription)"))
                return result
            }
            chunksRead += 1
            cursor = chunkStart
            // Progress is per-chunk; once the cap is hit the scan stops early
            // and we jump straight to 1.0.
            let fraction = kept.count >= cap
                ? 1.0
                : min(0.95, 0.05 + 0.9 * Double(chunksRead) / Double(totalChunks))
            progress(LoadProgress(fraction: fraction,
                                  stage: "Read \(kept.count.formatted()) records",
                                  recordsSoFar: kept.count))
            if cursor <= interval.start { break }
        }

        if kept.isEmpty {
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .info,
                message: "No unified-log records in the selected range."))
            return result
        }

        if kept.count >= cap {
            // Be explicit about what was and was not read — no silent
            // truncation and no invented totals.
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .warning,
                message: "Showing the most recent \(cap.formatted()) records, read from the last \(max(1, Int(interval.end.timeIntervalSince(firstChunkStart) / 60))) min of the selected range (\(chunksRead) scan(s)). Narrow the time range or add filters to see more."))
        }

        // Resolve executable paths from a single process-table pass, not one
        // scan per record (see ProcessPathResolver.pathMap).
        progress(LoadProgress(fraction: 0.97, stage: "Resolving process paths",
                              recordsSoFar: kept.count))
        let paths = ProcessPathResolver.pathMap()
        result.events = kept.map { normalize($0, paths: paths) }.sorted { $0.timestamp > $1.timestamp }
        progress(LoadProgress(fraction: 1, stage: "Done", recordsSoFar: kept.count))
        return result
    }

    private func normalize(_ entry: OSLogEntry, paths: [String: String]) -> LogEvent {
        var process = "—"
        var executable = "—"
        var subsystem = ""
        var category = ""
        var severity: Severity = .info

        if let l = entry as? OSLogEntryLog {
            process = l.process
            subsystem = l.subsystem
            category = l.category
            severity = Severity(osLogLevel: l.level)
            executable = paths[l.process] ?? "—"
        } else if let a = entry as? OSLogEntryActivity {
            process = a.process
            executable = paths[a.process] ?? "—"
            severity = .info
        } else if let s = entry as? OSLogEntrySignpost {
            subsystem = s.subsystem
            category = s.category
            process = "—"
            severity = .debug
        }

        let message = entry.composedMessage
        let all = SourceCategory.classifyAll(process: process, message: message, subsystem: subsystem)
        return LogEvent(
            timestamp: entry.date,
            process: process,
            executablePath: executable,
            message: message,
            subsystem: subsystem,
            category: category,
            severity: severity,
            source: all.first ?? .other,
            eventType: classifyEventType(message: message, level: severity),
            rawRecord: rawRepresentation(of: entry, process: process, subsystem: subsystem, category: category),
            collectorID: id
        )
    }

    /// The original record, assembled from the fields the system recorded. We
    /// present what the log store holds; we never re-word it.
    private func rawRepresentation(of entry: OSLogEntry, process: String, subsystem: String, category: String) -> String {
        let level: String
        if let l = entry as? OSLogEntryLog {
            level = String(describing: l.level)
        } else if entry is OSLogEntrySignpost {
            level = "signpost"
        } else {
            level = "activity"
        }
        var parts: [String] = []
        parts.append(Stamp.full.string(from: entry.date))
        parts.append(level)
        if !subsystem.isEmpty { parts.append("subsystem: \(subsystem)") }
        if !category.isEmpty { parts.append("category: \(category)") }
        if process != "—" { parts.append("process: \(process)") }
        parts.append("— \(entry.composedMessage)")
        return parts.joined(separator: "  ")
    }
}

extension Severity {
    public init(osLogLevel level: OSLogEntryLog.Level) {
        switch level {
        case .debug: self = .debug
        case .info: self = .info
        case .notice: self = .notice
        case .error: self = .error
        case .fault: self = .fault
        case .undefined: self = .info
        @unknown default: self = .info
        }
    }
}

/// Heuristic event-type label. Presentation only — it never replaces the message.
func classifyEventType(message: String, level: Severity) -> String {
    let m = message.lowercased()
    if level >= .error { return "Error" }
    if m.contains("fail") { return "Failure" }
    if m.contains("warn") || level == .warning { return "Warning" }
    if m.contains("install") { return "Installation" }
    if m.contains("download") || m.contains("upload") { return "Transfer" }
    if m.contains("enroll") || m.contains("check-in") || m.contains("checkin") { return "Enrollment" }
    if m.contains("command") { return "Command" }
    if m.contains("profile") { return "Profile" }
    if m.contains("certificate") || m.contains("scep") { return "Certificate" }
    if m.contains("update") { return "Software Update" }
    if m.contains("inventory") || m.contains("sensor") { return "Inventory" }
    if m.contains("script") || m.contains("freestyle") { return "Script / Workflow" }
    if m.contains("auth") || m.contains("sso") || m.contains("token") { return "Authentication" }
    if m.contains("connect") || m.contains("network") || m.contains("dns") { return "Network" }
    if level == .debug { return "Debug" }
    return "Activity"
}
