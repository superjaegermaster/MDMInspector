import Foundation
import SwiftUI

/// Central application state. Owns collectors, the loaded snapshot, filters and
/// the live tail. No persistent store, no background collector in historical
/// mode (§2.3) — the snapshot is only reloaded on explicit Refresh.
@MainActor
public final class InspectorModel: ObservableObject {
    // View state
    @Published var appMode: AppMode = .dashboard
    @Published var runMode: RunMode = .historical
    @Published var timeRange: TimeRange = .m30
    @Published var displayMode: DisplayMode = .detailed
    @Published var selectedSource: SourceCategory = .all
    @Published var searchText: String = ""
    @Published var severityFilter: Set<Severity> = []
    @Published var selectedProcess: String?
    @Published public var selectedEvent: LogEvent?
    @Published var shouldFollow = true
    @Published var inspectorVisible = true

    // Data
    @Published public private(set) var events: [LogEvent] = []
    @Published public private(set) var diagnostics: [DiagnosticEvent] = []
    @Published public private(set) var isLoading = false
    /// Overall 0...1 across all collectors, or nil when a collector cannot
    /// predict. Drives the progress bar shown during a load.
    @Published public private(set) var loadProgress: Double?
    @Published public private(set) var loadStage: String = ""
    /// Records found so far in the current load, summed across every collector.
    /// A real count: each collector reports how many it has produced as it
    /// streams them, so the number only ever grows and always reflects evidence.
    @Published public private(set) var logsDiscovered: Int = 0
    @Published public private(set) var lastLoaded: Date?
    @Published public private(set) var capabilities: [String: CapabilityStatus] = [:]

    let collectors: [any LogCollector]

    /// Records pulled in per source on a single snapshot load.
    private let perCollectorLimit = 4000
    /// Unified-log events kept in memory; the largest source by far.
    private let unifiedEventLimit = 20000

    public init(collectors: [any LogCollector] = CollectorRegistry.makeCollectors()) {
        self.collectors = collectors
        refreshCapabilities()
        applyLaunchArguments()
    }

    /// Supports `-startView timeline|capabilities|dashboard`,
    /// `-timeRange 5m|15m|30m|1h|4h|24h` and `-displayMode grouped|detailed|raw`
    /// so any pane can be opened directly for verification without having to
    /// drive the segmented controls by hand.
    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        var i = 1
        while i < args.count - 1 {
            let key = args[i]
            let value = args[i + 1]
            if key == "-startView", let mode = AppMode(rawValue: value.capitalized) {
                appMode = mode
            } else if key == "-timeRange", let range = TimeRange(rawValue: value.lowercased()) {
                timeRange = range
            } else if key == "-displayMode", let dm = DisplayMode(rawValue: value.capitalized) {
                displayMode = dm
            }
            i += 2
        }
    }

    // MARK: - Derived data

    /// Events passing source + severity + process + text filters, newest first.
    public var filteredEvents: [LogEvent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let terms = query.isEmpty ? [] : query.split(separator: " ").map(String.init)

        return events.filter { e in
            // An event can belong to several categories; any match includes it.
            if selectedSource != .all && !e.matches(selectedSource) { return false }
            if !severityFilter.isEmpty && !severityFilter.contains(e.severity) { return false }
            if let p = selectedProcess, e.process != p { return false }
            if !terms.isEmpty {
                let blob = e.searchBlob
                for t in terms where !blob.contains(t) { return false }
            }
            return true
        }
    }

    public var statistics: (events: Int, errors: Int, warnings: Int, sources: Int) {
        let f = filteredEvents
        return (
            events: f.count,
            errors: f.filter { $0.severity >= .error }.count,
            warnings: f.filter { $0.severity == .warning }.count,
            sources: Set(f.flatMap(\.sources)).count
        )
    }

    /// Recent errors for the dashboard (§11).
    var recentErrors: [LogEvent] {
        filteredEvents.filter { $0.severity >= .error }.prefix(50).map { $0 }
    }

    /// Activity volume per source, descending.
    var activityBySource: [(source: SourceCategory, count: Int)] {
        var counts: [SourceCategory: Int] = [:]
        // A cross-domain event counts toward each category it belongs to.
        for e in filteredEvents { for c in e.sources { counts[c, default: 0] += 1 } }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    /// Process/source-based groups (§18). Presentation only.
    var groups: [EventGroup] {
        var order: [String] = []
        var buckets: [String: [LogEvent]] = [:]
        for e in filteredEvents {
            let key = e.process
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(e)
        }
        return order.map { key in
            let list = buckets[key] ?? []
            let subs = Set(list.map(\.subsystem)).sorted()
            return EventGroup(
                id: key,
                title: key,
                subtitle: subs.first ?? "",
                events: list
            )
        }
    }

    /// Discovered processes, for the structured process filter.
    var discoveredProcesses: [String] {
        Array(Set(events.map(\.process))).sorted()
    }

    var isEmpty: Bool { events.isEmpty }

    // MARK: - Actions

    func refreshCapabilities() {
        for c in collectors { capabilities[c.id] = c.probe() }
    }

    /// Manual Refresh (§10): reloads the historical snapshot.
    ///
    /// Collectors run sequentially so the log store is hit once and progress is
    /// meaningful. `loadProgress` moves monotonically across the whole pass:
    /// collectors that cannot estimate still advance the bar by their share on
    /// completion, so the bar never stalls or jumps backwards.
    public func refresh() async {
        guard !isLoading else { return }     // ignore re-entrant refreshes
        isLoading = true
        loadStage = "Starting"
        loadProgress = 0
        logsDiscovered = 0
        var finishedRecords = 0        // records from collectors already done
        // Deliberately NOT nil-ing loadProgress here: the final 100% stays
        // readable after the load finishes (the bar itself is hidden by
        // `isLoading`), which is what makes the value verifiable.
        defer { isLoading = false }

        let interval = timeRange.interval()
        let total = max(1, collectors.count)
        var collected: [LogEvent] = []
        var diags: [DiagnosticEvent] = []

        for (index, collector) in collectors.enumerated() {
            let base = Double(index) / Double(total)
            let share = 1.0 / Double(total)
            let limit = collector.id == "unified" ? unifiedEventLimit : perCollectorLimit

            // Each collector owns only its slice of the bar.
            let handler: ProgressHandler = { [weak self] p in
                guard let self = self else { return }
                let within = p.fraction.map { min(1, max(0, $0)) }
                let overall = base + share * (within ?? 0)
                Task { @MainActor in
                    self.loadProgress = overall
                    self.loadStage = "\(collector.displayName) — \(p.stage)"
                    // Live total: everything already finished plus what the
                    // current collector has streamed so far.
                    self.logsDiscovered = finishedRecords + p.recordsSoFar
                }
            }

            let result = await collector.collect(interval: interval, limit: limit, progress: handler)
            collected.append(contentsOf: result.events)
            diags.append(contentsOf: result.diagnostics)
            capabilities[collector.id] = collector.probe()
            finishedRecords += result.events.count

            // Guarantee forward progress even for collectors with no estimate.
            loadProgress = base + share
            loadStage = "\(collector.displayName) — done"
        }

        loadStage = "Sorting \(collected.count.formatted()) events"
        logsDiscovered = collected.count
        events = collected.sorted { $0.timestamp > $1.timestamp }
        diagnostics = diags
        lastLoaded = Date()
        refreshCapabilities()
        loadProgress = 1
        loadStage = "Loaded"
    }

    /// Change the range and reload the snapshot.
    func changeRange(_ range: TimeRange) async {
        timeRange = range
        await refresh()
    }

    /// Live mode: re-reads the tail of the unified log at a short interval and
    /// appends only records newer than what we already hold. Uses the same UI.
    func startLive() async {
        runMode = .live
        events = []
        shouldFollow = true
        await refresh()
        Task { [weak self] in
            while let self = self, self.runMode == .live {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard self.runMode == .live else { break }
                await self.pollLive()
            }
        }
    }

    func stopLive() {
        runMode = .historical
    }

    private func pollLive() async {
        guard let unified = collectors.first(where: { $0.id == "unified" }) else { return }
        let from = lastLoaded ?? Date().addingTimeInterval(-60)
        let result = await unified.collect(interval: DateInterval(start: from, end: Date()), limit: 2000)
        let fresh = result.events.filter { e in !self.events.contains(where: { $0.id == e.id }) }
        // De-dup by (timestamp, process, message) since OSLogStore re-reads overlap.
        let known = Set(self.events.map { "\($0.timestamp.timeIntervalSince1970)|\($0.process)|\($0.message)" })
        let additions = fresh.filter { !known.contains("\($0.timestamp.timeIntervalSince1970)|\($0.process)|\($0.message)") }
        guard !additions.isEmpty else { return }
        self.events = (self.events + additions).sorted { $0.timestamp > $1.timestamp }
        if self.events.count > self.unifiedEventLimit {
            self.events = Array(self.events.suffix(self.unifiedEventLimit))
        }
    }

    func clearFilters() {
        searchText = ""
        severityFilter = []
        selectedSource = .all
        selectedProcess = nil
    }

    /// Jump from a dashboard error to its event in the timeline (§11).
    public func open(_ event: LogEvent) {
        selectedEvent = event
        selectedProcess = nil
        appMode = .timeline
    }

    public func copyRawRecord(_ event: LogEvent) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(event.rawRecord, forType: .string)
    }
}
