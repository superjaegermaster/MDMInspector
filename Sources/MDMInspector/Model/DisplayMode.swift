import Foundation

/// Timeline display modes (§17). Correlation is presentation, not destruction —
/// every mode renders every event that passed the filters.
public enum DisplayMode: String, CaseIterable, Identifiable {
    case grouped = "Grouped"
    case detailed = "Detailed"
    case raw = "Raw"

    public var id: String { rawValue }
    public var label: String { rawValue }
}

public enum AppMode: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case timeline = "Timeline"
    case capabilities = "Capabilities"

    public var id: String { rawValue }
    public var label: String { rawValue }
}

public enum RunMode: String, CaseIterable, Identifiable {
    case historical = "Historical"
    case live = "LIVE"

    public var id: String { rawValue }
    public var label: String { rawValue }
}
