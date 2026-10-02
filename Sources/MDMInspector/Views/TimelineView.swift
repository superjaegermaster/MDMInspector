import SwiftUI

/// Three-pane investigation layout (§9): Sources | Timeline | Inspector.
public struct TimelineView: View {
    @EnvironmentObject public var model: InspectorModel

    public var body: some View {
        HSplitView {
            SourcesSidebar()
                .frame(minWidth: 175, idealWidth: 190, maxWidth: 260)
            VStack(spacing: 0) {
                FilterBar()
                Divider()
                timelineBody
            }
            .frame(minWidth: 480)
            if model.inspectorVisible {
                InspectorPane()
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 480)
            }
        }
    }

    @ViewBuilder
    private var timelineBody: some View {
        if model.events.isEmpty && !model.isLoading {
            VStack(spacing: 10) {
                Image(systemName: "tray").font(.system(size: 34)).foregroundStyle(.tertiary)
                Text("No events loaded for \(model.timeRange.label.lowercased()).")
                    .foregroundStyle(.secondary)
                Button("Refresh") { Task { await model.refresh() } }
                Text("If this Mac restricts log access, check the Capabilities tab for Full Disk Access.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch model.displayMode {
            case .grouped: GroupedTimeline()
            case .detailed: DetailedTimeline()
            case .raw: RawTimeline()
            }
        }
    }
}

// MARK: - Sources sidebar (§23)

public struct SourcesSidebar: View {
    @EnvironmentObject public var model: InspectorModel

    public var body: some View {
        List(selection: $model.selectedSource) {
            Section("Sources") {
                ForEach(SourceCategory.sidebarOrder) { source in
                    HStack(spacing: 7) {
                        Circle().fill(source.color).frame(width: 8, height: 8)
                        Text(source.label)
                        Spacer()
                        Text(count(for: source).formatted())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .tag(source)
                }
            }
            if !model.discoveredProcesses.isEmpty {
                Section("Processes (discovered)") {
                    ForEach(model.discoveredProcesses.prefix(200), id: \.self) { p in
                        HStack(spacing: 6) {
                            Image(systemName: "terminal").font(.system(size: 9)).foregroundStyle(.tertiary)
                            Text(p).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                        }
                        .tag(SourceCategory.other)  // selection handled via process filter
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectedProcess = p; model.selectedSource = .all }
                        .background(model.selectedProcess == p ? Color.accentColor.opacity(0.18) : .clear)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func count(for source: SourceCategory) -> Int {
        if source == .all { return model.filteredEvents.count }
        return model.filteredEvents.filter { $0.matches(source) }.count
    }
}

// MARK: - Filter bar

public struct FilterBar: View {
    @EnvironmentObject public var model: InspectorModel

    public var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search message, process, path, subsystem, category", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !model.searchText.isEmpty {
                    Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            .frame(minWidth: 260)

            Menu {
                ForEach(Severity.allCases, id: \.self) { s in
                    Toggle(isOn: Binding(
                        get: { model.severityFilter.contains(s) },
                        set: { on in
                            if on { model.severityFilter.insert(s) } else { model.severityFilter.remove(s) }
                        })) { Text(s.label) }
                }
                Divider()
                Button("All severities") { model.severityFilter = [] }
            } label: {
                Label(model.severityFilter.isEmpty ? "Severity" : "Severity (\(model.severityFilter.count))",
                      systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 150)

            Picker("", selection: $model.displayMode) {
                ForEach(DisplayMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)

            Button {
                model.inspectorVisible.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Toggle inspector")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

// MARK: - Detailed timeline

public struct DetailedTimeline: View {
    @EnvironmentObject public var model: InspectorModel

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.filteredEvents) { event in
                        EventRow(event: event, compact: false)
                            .id(event.id)
                            .onTapGesture { model.selectedEvent = event }
                        Divider().opacity(0.35)
                    }
                }
            }
            .onChange(of: model.filteredEvents.count) { _, _ in
                if model.runMode == .live && model.shouldFollow {
                    if let last = model.filteredEvents.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }
}

public struct EventRow: View {
    public let event: LogEvent
    public let compact: Bool
    @EnvironmentObject public var model: InspectorModel

    public var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(Stamp.timeWithMillis.string(from: event.timestamp))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)

            Text(event.severity.glyph)
                .foregroundStyle(event.severity.color)
                .frame(width: 12)

            Circle().fill(event.source.color).frame(width: 8, height: 8).padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.system(size: 12))
                    .lineLimit(compact ? 1 : 4)
                    .fixedSize(horizontal: false, vertical: true)
                if !compact {
                    HStack(spacing: 8) {
                        Text(event.process)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                        Text(event.sourceLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(event.eventType)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if !event.subsystem.isEmpty {
                            Text(event.subsystem)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 3 : 5)
        .background(
            model.selectedEvent?.id == event.id
                ? Color.accentColor.opacity(0.16)
                : (event.severity >= .error ? event.severity.color.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Grouped timeline (§18)

public struct GroupedTimeline: View {
    @EnvironmentObject public var model: InspectorModel

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.groups) { group in
                    DisclosureGroup {
                        ForEach(group.events) { event in
                            EventRow(event: event, compact: true)
                                .onTapGesture { model.selectedEvent = event }
                            Divider().opacity(0.3)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                            Text(group.title)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Text(group.subtitle)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Text("\(group.events.count)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Raw timeline (§21 — the record itself)

public struct RawTimeline: View {
    @EnvironmentObject public var model: InspectorModel

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.filteredEvents) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.rawRecord)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(Stamp.timeWithMillis.string(from: event.timestamp))  ·  \(event.process)  ·  \(event.source.label)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(model.selectedEvent?.id == event.id ? Color.accentColor.opacity(0.16) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectedEvent = event }
                    Divider().opacity(0.3)
                }
            }
        }
    }
}
