import Foundation

/// Predefined historical ranges (§8). Custom ranges are deferred.
public enum TimeRange: String, CaseIterable, Identifiable {
    case m5 = "5m"
    case m15 = "15m"
    case m30 = "30m"
    case h1 = "1h"
    case h4 = "4h"
    case h24 = "24h"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .m5: return "Last 5 minutes"
        case .m15: return "Last 15 minutes"
        case .m30: return "Last 30 minutes"
        case .h1: return "Last 1 hour"
        case .h4: return "Last 4 hours"
        case .h24: return "Last 24 hours"
        }
    }

    public var shortLabel: String {
        switch self {
        case .m5: return "5m"
        case .m15: return "15m"
        case .m30: return "30m"
        case .h1: return "1h"
        case .h4: return "4h"
        case .h24: return "24h"
        }
    }

    public var seconds: TimeInterval {
        switch self {
        case .m5: return 5 * 60
        case .m15: return 15 * 60
        case .m30: return 30 * 60
        case .h1: return 3600
        case .h4: return 4 * 3600
        case .h24: return 24 * 3600
        }
    }

    func interval(endingAt end: Date = Date()) -> DateInterval {
        DateInterval(start: end.addingTimeInterval(-seconds), end: end)
    }
}

/// Millisecond-precision timestamp formatting (§15).
public enum Stamp {
    public static let withMillis: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    public static let timeWithMillis: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    public static let full: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
}
