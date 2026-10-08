import Foundation
import SwiftUI

/// Central application state. Owns collectors, the loaded snapshot, filters and
/// the loaded snapshot. No persistent store and no background collector: a
/// snapshot is only reloaded on explicit Refresh.
@MainActor
public final class InspectorModel: ObservableObject {
    // View state
    @Published var appMode: AppMode = .dashboard
    @Published var timeRange: TimeRange = .m5
    @Published var displayMode: DisplayMode = .detailed
    @Published var selectedSource: SourceCategory = .all
    @Published var searchText: String = ""
    @Published var severityFilter: Set<Severity> = []
    @Published var selectedProcess: String?
    @Published public var selectedEvent: LogEvent?
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
    /// Deferred selection request from `-selectEvent`.
    private enum PendingSelection { case first, firstError }
    private var selectFirst: PendingSelection?

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
            } else if key == "-selectEvent" {
                // "first" or "firstError": preselect an event once data has
                // loaded, so the Inspector pane can be captured without having
                // to synthesise clicks into a SwiftUI scroll view.
                selectFirst = (value == "firstError") ? .firstError : .first
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

    /// Activity volume per topic, descending. All MDM products share one
    /// Dashboard topic while their detailed source labels remain available.
    var activityBySource: [(source: SourceCategory, count: Int)] {
        var counts: [SourceCategory: Int] = [:]
        for e in filteredEvents {
            let topics = e.sources.contains { $0 == .mdm || $0 == .workspaceOne || $0 == .intune || $0 == .jamf }
                ? (e.sources.filter { ![.workspaceOne, .intune, .jamf].contains($0) } + [.mdm])
                : e.sources
            for c in Set(topics) { counts[c, default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    /// Topic-based groups for the grouped timeline. MDM products are one
    /// topic: Apple MDM, Kandji, Intune, Workspace ONE, Jamf and Mosyle.
    var groups: [EventGroup] {
        var order: [SourceCategory] = []
        var buckets: [SourceCategory: [LogEvent]] = [:]
        for e in filteredEvents {
            let topic: SourceCategory = e.matches(.mdm) ? .mdm : (e.sources.first ?? .other)
            if buckets[topic] == nil { order.append(topic) }
            buckets[topic, default: []].append(e)
        }
        return order.map { topic in
            let list = buckets[topic] ?? []
            return EventGroup(id: topic.rawValue, title: topic.label,
                              subtitle: topic == .mdm ? "Apple MDM, Kandji, Intune, Workspace ONE, Jamf and Mosyle" : "\(list.count) records",
                              events: list)
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
                    // Collector callbacks can finish on different tasks. Do not
                    // let an older callback overwrite a newer progress sample.
                    guard overall >= (self.loadProgress ?? 0) else { return }
                    self.loadProgress = overall
                    self.loadStage = "\(collector.displayName) — \(p.stage)"
                    // Records discovered so far is also monotonic within a load.
                    self.logsDiscovered = max(self.logsDiscovered, finishedRecords + p.recordsSoFar)
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
        applyPendingSelection()
        loadProgress = 1
        loadStage = "Loaded"
    }

    /// Honour a `-selectEvent` request once events exist.
    private func applyPendingSelection() {
        guard let want = selectFirst, !events.isEmpty else { return }
        selectFirst = nil
        if want == .firstError {
            selectedEvent = events.first { $0.severity >= .error } ?? events[0]
        } else {
            selectedEvent = events[0]
        }
    }

    /// Change the range and reload the snapshot.
    func changeRange(_ range: TimeRange) async {
        timeRange = range
        await refresh()
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
