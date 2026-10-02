import SwiftUI

public struct RootView: View {
    public init() {}
    @EnvironmentObject public var model: InspectorModel

    public var body: some View {
        VStack(spacing: 0) {
            TopBar()
            LoadProgressBar()
            Divider()
            switch model.appMode {
            case .dashboard: DashboardView()
            case .timeline: TimelineView()
            case .capabilities: CapabilitiesView()
            }
            Divider()
            StatusBar()
        }
        .frame(minWidth: 1180, minHeight: 700)
    }
}

// MARK: - Top bar

public struct TopBar: View {
    @EnvironmentObject public var model: InspectorModel

    public var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(.tint)
                Text("MDM Inspector")
                    .font(.system(size: 15, weight: .semibold))
            }

            Picker("", selection: $model.appMode) {
                ForEach(AppMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 340)

            Spacer(minLength: 12)

            if model.appMode != .capabilities {
                Picker("", selection: $model.runMode) {
                    ForEach(RunMode.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 150)
                .onChange(of: model.runMode) { _, new in
                    Task {
                        if new == .live { await model.startLive() } else { model.stopLive() }
                    }
                }

                Picker("", selection: $model.timeRange) {
                    ForEach(TimeRange.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 170)
                .onChange(of: model.timeRange) { _, new in
                    Task { await model.changeRange(new) }
                }

                Button {
                    Task { await model.refresh() }
                } label: {
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isLoading)
                .help("Reload the snapshot for the selected time range")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

// MARK: - Loading

/// Progress bar shown while a snapshot loads.
///
/// Shows the current source, a real running count of the records discovered so
/// far, and a percentage when a source can estimate one (indeterminate when it
/// cannot). The bar breathes gently while loading so a long load reads as alive
/// rather than stuck.
public struct LoadProgressBar: View {
    @EnvironmentObject public var model: InspectorModel

    public init() {}

    public var body: some View {
        if model.isLoading {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if model.loadProgress == nil {
                        ProgressView().controlSize(.small)
                    }
                    // Gentle blink, driven by TimelineView rather than @State:
                    // this toolchain has no SwiftUIMacros, so @State will not
                    // compile, but a time-based redraw works fine and gives a
                    // smooth pulse instead of a step change.
                    SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                        let phase = sin(ctx.date.timeIntervalSinceReferenceDate * 3.4)
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .scaleEffect(1.0 + 0.22 * phase)
                            .opacity(0.55 + 0.45 * (phase + 1) / 2)
                            .frame(width: 14)
                    }
                    .frame(width: 14)

                    Text(model.loadStage.isEmpty ? "Loading events…" : model.loadStage)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    // Live count of records found so far. Real evidence: each
                    // collector reports what it has actually streamed.
                    Text("\(model.logsDiscovered.formatted()) logs")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())

                    if let p = model.loadProgress {
                        Text("\(Int((p * 100).rounded()))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                    let phase = sin(ctx.date.timeIntervalSinceReferenceDate * 3.4)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: max(3, geo.size.width * (model.loadProgress ?? 0.28)))
                                .opacity(0.78 + 0.22 * (phase + 1) / 2)
                        }
                    }
                }
                .frame(height: 5)
                .animation(.easeOut(duration: 0.25), value: model.loadProgress)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

// MARK: - Status bar

public struct StatusBar: View {
    @EnvironmentObject public var model: InspectorModel

    public var body: some View {
        HStack(spacing: 12) {
            Text("Local only — no data leaves this Mac")
                .foregroundStyle(.secondary)
            Divider().frame(height: 12)
            if model.isLoading {
                Text("loading…")
                    .foregroundStyle(.tint)
                Text("\(model.logsDiscovered.formatted()) logs so far")
            } else {
                Text("\(model.events.count.formatted()) events loaded")
                Text("\(model.filteredEvents.count.formatted()) shown")
            }
            if let last = model.lastLoaded {
                Text("Snapshot \(Stamp.timeWithMillis.string(from: last))")
            }
            if model.runMode == .live {
                Text("● LIVE").foregroundStyle(.red).fontWeight(.semibold)
                Text(model.shouldFollow ? "following" : "paused — scrolled up")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !model.diagnostics.isEmpty {
                Menu {
                    ForEach(model.diagnostics.prefix(50)) { d in
                        Text("\(d.level.rawValue.uppercased()) · \(d.collector): \(d.message)")
                    }
                } label: {
                    Label("\(model.diagnostics.count) source messages", systemImage: "info.circle")
                }
                .menuStyle(.borderlessButton)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.bar)
    }
}
