import SwiftUI

/// Dashboard: a factual snapshot of the selected historical range (§11).
/// Descriptive, not diagnostic — no health score, no root cause.
public struct DashboardView: View {
    @EnvironmentObject public var model: InspectorModel

    private var stats: (events: Int, errors: Int, warnings: Int, sources: Int) { model.statistics }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statRow
                HStack(alignment: .top, spacing: 18) {
                    recentErrors
                    activityBySource
                }
            }
            .padding(18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.timeRange.label)
                .font(.system(size: 22, weight: .semibold))
            Text("Snapshot of local activity on this Mac. Described, not diagnosed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            StatCard(title: "Events", value: stats.events, tint: .blue, systemImage: "list.bullet.rectangle")
            StatCard(title: "Errors", value: stats.errors, tint: .red, systemImage: "xmark.octagon")
            StatCard(title: "Warnings", value: stats.warnings, tint: .orange, systemImage: "exclamationmark.triangle")
            StatCard(title: "Sources", value: stats.sources, tint: .purple, systemImage: "square.stack.3d.up")
        }
    }

    private var recentErrors: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Errors").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(model.recentErrors.count)").foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                if model.recentErrors.isEmpty {
                    Text("No errors in this range.")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    ForEach(model.recentErrors) { event in
                        Button {
                            model.open(event)
                        } label: {
                            ErrorRow(event: event)
                        }
                        .buttonStyle(.plain)
                        if event.id != model.recentErrors.last?.id { Divider() }
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activityBySource: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity by Source").font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 7) {
                let rows = model.activityBySource
                let maxCount = rows.map(\.count).max() ?? 1
                if rows.isEmpty {
                    Text("No activity in this range.").foregroundStyle(.secondary).font(.system(size: 12))
                }
                ForEach(rows.prefix(14), id: \.source) { row in
                    Button {
                        model.selectedSource = row.source
                        model.appMode = .timeline
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(row.source.color).frame(width: 8, height: 8)
                            Text(row.source.label)
                                .font(.system(size: 12))
                                .frame(width: 120, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(row.source.color.opacity(0.75))
                                    .frame(width: Swift.max(2, geo.size.width * Double(row.count) / Double(maxCount)), height: 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 12)
                            Text(row.count.formatted())
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
        .frame(width: 400)
    }
}

public struct StatCard: View {
    public let title: String
    public let value: Int
    public let tint: Color
    public let systemImage: String

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(tint)
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(value.formatted())
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
    }
}

public struct ErrorRow: View {
    public let event: LogEvent

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Stamp.timeWithMillis.string(from: event.timestamp))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Circle().fill(event.source.color).frame(width: 8, height: 8).padding(.top, 3)
            Text(event.process)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 150, alignment: .leading)
            Text(event.message)
                .font(.system(size: 12))
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(event.eventType)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}
