import Foundation

/// MVP-3 (first pass): plain-text / rotated log files on this Mac, e.g.
/// `/var/log/install.log`, Intelligent Hub logs, agent logs. Parsing is
/// intentionally generic: the original line is always preserved verbatim as
/// `rawRecord`, and anything we cannot parse simply does not become an event.
public final class FileLogCollector: LogCollector {
    public let id: String
    public let displayName: String
    public let detail: String
    public let path: String

    /// Per-refresh budgets for folder sources. A folder can hold thousands of
    /// files; without these, one refresh can take minutes and read gigabytes.
    private let maxFileSize = 32 * 1024 * 1024
    private let maxBytesPerDirectory = 64 * 1024 * 1024

    public init(id: String, displayName: String, path: String, detail: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.detail = detail ?? path
    }

    public func probe() -> CapabilityStatus {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            return .unavailable("Not present on this Mac")
        }
        // Read for real rather than trusting isReadableFile, which only checks
        // the mode bits and happily reports a path as readable when an ancestor
        // directory blocks traversal (EPERM on the way in, not on the file).
        do {
            if isDir.boolValue {
                _ = try FileManager.default.contentsOfDirectory(atPath: path)
                return .available("Directory readable")
            } else {
                _ = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                return .available("Readable")
            }
        } catch let e as NSError {
            return Self.status(for: e, path: path)
        } catch {
            return .unavailable("Cannot read \(path): \(error.localizedDescription)")
        }
    }

    /// Classifies a read failure without guessing at its cause.
    ///
    /// "Not permitted" is reported as a permission problem because the OS said
    /// so. Everything else - a vanished file, a directory where a file was
    /// expected, a broken symlink - is reported as what it is. Telling a user to
    /// open System Settings when the real fault is a dangling path is worse than
    /// no message at all.
    static func status(for error: NSError, path: String) -> CapabilityStatus {
        let denied = error.domain == NSCocoaErrorDomain && [
            NSFileReadNoPermissionError, NSFileWriteNoPermissionError
        ].contains(error.code)

        if denied {
            return .permissionRequired(
                "macOS denied reading \(path) (NSFileReadNoPermissionError). Full Disk Access (System Settings → Privacy & Security → Full Disk Access) is the usual fix.")
        }
        if error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return .unavailable("Not present on this Mac (\(path))")
        }
        return .unavailable("Cannot read \(path): \(error.localizedDescription)")
    }

    public func collect(interval: DateInterval, limit: Int) async -> CollectResult {
        await collect(interval: interval, limit: limit, progress: { _ in })
    }

    public func collect(interval: DateInterval, limit: Int,
                        progress: @escaping ProgressHandler) async -> CollectResult {
        var result = CollectResult()
        progress(LoadProgress(fraction: nil, stage: "Reading \(displayName)"))

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            // A source that simply is not installed is not an error and must
            // not be reported as a permissions problem.
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .info,
                message: "Not present on this Mac (\(path))."))
            return result
        }
        if isDir.boolValue {
            return collectDirectory(interval: interval, limit: limit, progress: progress)
        }

        guard let text = readTail(path: path, interval: interval, progress: progress) else {
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .error,
                message: "Cannot read \(path). Grant Full Disk Access and retry."))
            return result
        }
        progress(LoadProgress(fraction: 0.8, stage: "Parsing records"))
        result.events = Array(parse(text, interval: interval).prefix(limit))
        progress(LoadProgress(fraction: 1, stage: "Done", recordsSoFar: result.events.count))
        if result.events.isEmpty {
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .info,
                message: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "File is empty."
                    : "No lines with a recognised timestamp in the selected range."))
        }
        return result
    }

    /// Reads only as much of the file as the time range can possibly need.
    ///
    /// `/var/log/install.log` grows to hundreds of MB on a managed Mac. Reading
    /// it whole and filtering afterwards took ~30s per refresh; walking the
    /// file backwards in chunks from the newest end lets us stop as soon as the
    /// lines predate the range. Returns nil only when the file is unreadable.
    private func readTail(path: String, interval: DateInterval,
                        progress: @escaping ProgressHandler) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) }
        }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd() else {
            return FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) }
        }

        let chunkSize = 4 * 1024 * 1024
        var lower = fileSize          // exclusive upper bound of the next chunk
        var collected: [String] = []  // earliest-first, so prepend as we go back

        while lower > 0 {
            let upper = lower
            progress(LoadProgress(fraction: lower == 0 ? 0.75 : 0.35 + 0.4 * Double(1 - Double(lower) / Double(max(fileSize, 1))),
                                  stage: "Reading \(max(0, (upper - lower) / 1024)) KB chunk"))
            lower = upper > UInt64(chunkSize) ? upper - UInt64(chunkSize) : 0

            try? handle.seek(toOffset: lower)
            guard let data = try? handle.read(upToCount: Int(upper - lower)), !data.isEmpty else { break }

            let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
            // When we did not start at byte 0 the first line is a fragment of a
            // line that continues in the previous chunk; drop it.
            let usable = lower == 0 ? lines : (lines.count > 1 ? Array(lines.dropFirst()) : [])
            collected.insert(contentsOf: usable, at: 0)

            // Once the oldest line in hand predates the range, everything
            // further back is older still — stop reading.
            if let oldest = oldestTimestamp(in: collected), oldest < interval.start { break }
        }
        return collected.joined(separator: "\n")
    }

    /// Oldest recognised timestamp in the given lines, if any.
    private func oldestTimestamp(in lines: [String]) -> Date? {
        var oldest: Date?
        for line in lines {
            guard let ts = parseTimestamp(line: line)?.timestamp else { continue }
            if oldest == nil || ts < oldest! { oldest = ts }
        }
        return oldest
    }

    /// For directory sources, read the files that hold timestamped text and
    /// merge them, newest first. Files that are not text, are too large, or
    /// were last modified before the requested range are skipped — an agent log
    /// folder can hold thousands of files and parsing all of them on every
    /// refresh is what makes a tool feel broken.
    private func collectDirectory(interval: DateInterval, limit: Int,
                                   progress: @escaping ProgressHandler) -> CollectResult {
        var result = CollectResult()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else {
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .error,
                message: "Cannot list \(path). Grant Full Disk Access and retry."))
            return result
        }

        var events: [LogEvent] = []
        var scanned = 0
        var skippedTooOld = 0
        var bytesRead = 0
        var budgetUsedUp = false

        // Newest files first, so the per-directory event budget is spent on the
        // records closest to "now" — the ones an admin is investigating.
        func modified(_ name: String) -> Date {
            let full = (path as NSString).appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let date = attrs[.modificationDate] as? Date else { return .distantPast }
            return date
        }
        let candidates = entries.sorted { modified($0) > modified($1) }

        let totalCandidates = max(1, candidates.count)
        for (index, name) in candidates.enumerated() {
            if index % 5 == 0 {
                progress(LoadProgress(fraction: Double(index) / Double(totalCandidates),
                                      stage: "\(displayName): file \(index + 1) of \(totalCandidates)",
                                      recordsSoFar: events.count))
            }
            if events.count >= limit || bytesRead >= maxBytesPerDirectory { budgetUsedUp = true; break }
            let full = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }

            // A file last modified before the range started cannot hold an
            // in-range record. Skipping it avoids reading the whole folder.
            let attrs = (try? fm.attributesOfItem(atPath: full)) ?? [:]
            if let modified = attrs[.modificationDate] as? Date, modified < interval.start {
                skippedTooOld += 1
                continue
            }
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0, size <= maxFileSize else { continue }
            guard bytesRead + size <= maxBytesPerDirectory else { continue }

            guard let data = fm.contents(atPath: full) else { continue }
            // Skip obvious binaries.
            guard let head = String(data: data.prefix(4096), encoding: .utf8),
                  head.contains("\n") || head.contains("20") else { continue }
            bytesRead += size
            scanned += 1
            events.append(contentsOf: parse(String(decoding: data, as: UTF8.self), interval: interval, fileName: name))
        }

        events.sort { $0.timestamp > $1.timestamp }
        result.events = Array(events.prefix(limit))
        progress(LoadProgress(fraction: 1, stage: "Done", recordsSoFar: result.events.count))

        if budgetUsedUp {
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .warning,
                message: "Stopped at \(scanned) files / \(bytesRead / 1024) KB of this folder (budget \(maxBytesPerDirectory / 1024 / 1024) MB). Newer files are shown first; narrow the time range for older records."))
        }

        if result.events.isEmpty {
            result.diagnostics.append(DiagnosticEvent(
                collector: displayName, level: .info,
                message: scanned == 0
                    ? (skippedTooOld > 0
                        ? "\(skippedTooOld) file(s) in this folder are older than the selected range."
                        : "No timestamped text files found in this folder.")
                    : "No lines with a recognised timestamp in the selected range."))
        }
        return result
    }

    private func parse(_ text: String, interval: DateInterval, fileName: String? = nil) -> [LogEvent] {
        var events: [LogEvent] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let raw = String(line)
            guard let parsed = parseTimestamp(line: raw) else { continue }
            guard parsed.timestamp >= interval.start, parsed.timestamp <= interval.end else { continue }
            events.append(makeEvent(timestamp: parsed.timestamp, message: parsed.message, raw: raw, fileName: fileName))
        }
        return events
    }

    /// A log file has no single owning process, so the file's identity is used
    /// as the process name. We never claim a process wrote something we cannot prove.
    private func makeEvent(timestamp: Date, message: String, raw: String, fileName: String?) -> LogEvent {
        let owner = ownerProcessName()
        let category = fileName ?? (path as NSString).lastPathComponent
        return LogEvent(
            timestamp: timestamp,
            process: owner,
            executablePath: ProcessPathResolver.path(forProcessName: owner) ?? "—",
            message: message,
            subsystem: "file:\(path)",
            category: category,
            severity: severity(from: raw),
            source: source(),
            eventType: classifyEventType(message: message, level: .info),
            rawRecord: raw,
            collectorID: id
        )
    }

    /// Maps a path to a source bucket. Vendor directories win over generic
    /// filename words, so `/var/log/jamfinstall.log` is Jamf rather than Apps.
    private func source() -> SourceCategory {
        let p = path.lowercased()
        if p.contains("airwatch") || p.contains("workspace") || p.contains("vmware") {
            return .workspaceOne
        }
        // Platform SSO evidence first: the Microsoft SSO extension lives inside
        // a Company Portal container, so a path-only rule would file genuine SSO
        // records under Intune.
        if p.contains("ssoextension") || p.contains("appsso") || p.contains("extensiblesso")
            || p.contains("okta") || p.contains("kerberos") || p.contains("macverify") {
            return .platformSSO
        }
        if p.contains("/library/logs/microsoft/intune") || p.contains("intunescripts")
            || p.contains("companyportal") || p.contains("onedrive") {
            return .intune
        }
        if p.contains("jamf") || p.contains("/usr/local/jamf") || p.contains("selfservice") {
            return .jamf
        }
        if p.contains("zscaler") || p.contains("tanium") || p.contains("cisco") { return .security }
        if p.contains("install") || p.contains("adobe") || p.contains("msi") { return .apps }
        if p.contains("mdm") || p.contains("profile") { return .mdm }
        if p.contains("wifi") { return .network }
        return .macOS
    }

    private func severity(from raw: String) -> Severity {
        let l = raw.lowercased()
        if l.contains("error") || l.contains("fail") || l.contains("fatal") { return .error }
        if l.contains("warn") { return .warning }
        if l.contains("debug") { return .debug }
        return .info
    }

    private func ownerProcessName() -> String {
        switch (path as NSString).lastPathComponent {
        case "install.log": return "installer"
        case "system.log": return "syslogd"
        case "appfirewall.log": return "socketfilterfw"
        case "wifi.log": return "airportd"
        default: return ((path as NSString).deletingPathExtension as NSString).lastPathComponent
        }
    }

    // MARK: - Timestamp parsing

    struct ParsedLine { let timestamp: Date; let message: String }

    private static let isoMillis: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static let isoNoFraction: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let syslog: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "MMM  d HH:mm:ss"
        return f
    }()

    /// Recognised shapes:
    ///   `2026-10-02 10:42:52.123456 host installer[123] message`
    ///   `2026-10-02 10:42:52 host installer[123] message`
    ///   `Oct  2 10:42:52 host installer[123] message`
    ///   `[1780000000.123456] message`
    private func parseTimestamp(line: String) -> ParsedLine? {
        let chars = Array(line.prefix(48))
        guard chars.count >= 12 else { return nil }

        // Year-first forms: try the two fixed-width shapes, then let the
        // formatter's leniency find the fraction.
        let isoPrefixLengths = [23, 19]
        for len in isoPrefixLengths where chars.count >= len {
            let candidate = String(chars.prefix(len))
            let f = len == 23 ? Self.isoMillis : Self.isoNoFraction
            if let ts = f.date(from: candidate) {
                return ParsedLine(timestamp: ts, message: trimmedRemainder(line, after: len))
            }
        }

        // syslog "Oct  2 10:42:52"
        let syslogLen = 15
        if chars.count >= syslogLen {
            let candidate = String(chars.prefix(syslogLen))
            if let ts = Self.syslog.date(from: candidate) {
                // A bare "Oct  2 HH:mm:ss" has no year; DateFormatter uses 2000.
                // Re-stamp with the current year so range filtering behaves.
                let year = Calendar.current.component(.year, from: Date())
                var comps = Calendar.current.dateComponents([.month, .day, .hour, .minute, .second], from: ts)
                comps.year = year
                if let fixed = Calendar.current.date(from: comps) {
                    return ParsedLine(timestamp: fixed, message: trimmedRemainder(line, after: syslogLen))
                }
            }
        }

        // Bracketed epoch: "[1780000000.123456] message"
        if line.hasPrefix("[") {
            if let close = line.firstIndex(of: "]") {
                let inner = line[line.index(after: line.startIndex)..<close]
                if let epoch = Double(inner), epoch > 1_000_000_000 {
                    return ParsedLine(timestamp: Date(timeIntervalSince1970: epoch),
                                      message: String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return nil
    }

    private func trimmedRemainder(_ line: String, after length: Int) -> String {
        guard line.count > length else { return "" }
        return String(line.dropFirst(length)).trimmingCharacters(in: .whitespaces)
    }
}
