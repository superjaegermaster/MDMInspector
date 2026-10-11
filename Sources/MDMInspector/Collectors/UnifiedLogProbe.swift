import Foundation
import OSLog

/// One shared, honest answer to "can this app read the unified log?"
///
/// The previous version of this lived inline in each unified-log collector and
/// did this:
///
/// ```swift
/// do { _ = try OSLogStore(scope: .system); return .available }
/// catch { return .permissionRequired("grant Full Disk Access") }
/// ```
///
/// That is wrong twice over. Creating the store proves almost nothing - the
/// constructor does not read anything - and mapping *any* failure to "grant Full
/// Disk Access" means a malformed predicate, a locked store or a bad date range
/// all get reported to the user as a privacy setting they need to change.
///
/// Measured on a Mac with no Full Disk Access grant, the store opens and
/// returns hundreds of thousands of entries. So "store opened" is not the test,
/// and Full Disk Access is not the thing that gates it. What FDA actually
/// changes is *redaction*: around 4% of entries contain `<private>` fields that
/// FDA unmasks. That is a real loss of information, but it is not an
/// inability to read, and conflating the two sends admins into System Settings
/// looking for a fix that was never required.
public enum UnifiedLogProbe {

    /// Result of a real read attempt.
    public struct Reading: Equatable, Sendable {
        public enum Outcome: Equatable, Sendable {
            /// Entries were read.
            case readable(entryCount: Int)
            /// The store opened but returned nothing for the window. Not a fault.
            case empty
            /// The store could not be opened at all.
            case storeUnavailable(reason: String)
        }

        public let outcome: Outcome
        /// How many of the sampled entries carried `<private>` fields.
        public let redactedInSample: Int
        public let sampleSize: Int

        public var isReadable: Bool {
            switch outcome {
            case .readable, .empty: return true
            case .storeUnavailable: return false
            }
        }

        /// Fraction of sampled entries with elided fields, e.g. 0.04 for 4%.
        public var redactionRate: Double {
            sampleSize > 0 ? Double(redactedInSample) / Double(sampleSize) : 0
        }
    }

    /// Cached result, so the read happens once per interval rather than once per
    /// collector.
    ///
    /// Every unified-log collector asks the same question of the same store, and
    /// `probe()` is called for all of them on every capability refresh. Without
    /// this each call re-read the window, which is what pushed a full refresh
    /// past ten minutes.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cached: [Int: (at: Date, reading: Reading)] = [:]

    /// Seconds a probe result stays valid. Long enough to collapse a full
    /// refresh into one read, short enough that re-checking permissions after a
    /// change actually notices.
    private static let ttl: TimeInterval = 30

    /// Reads, or returns the recent cached result.
    public static func readCached(window: TimeInterval = 300) -> Reading {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let key = max(1, Int(window.rounded()))
        if let c = cached[key], Date().timeIntervalSince(c.at) < ttl {
            return c.reading
        }
        let r = read(window: window)
        cached[key] = (Date(), r)
        return r
    }

    /// Drops the cache, so the next probe re-reads. For tests and for the
    /// "re-check permissions" action.
    public static func invalidateCache() {
        cacheLock.lock()
        cached.removeAll(keepingCapacity: true)
        cacheLock.unlock()
    }

    /// Actually reads a short window, and reports what happened.
    ///
    /// The window is deliberately tiny: this runs for every registered source on
    /// every capability refresh, and the goal is to prove readability, not to
    /// harvest records. 200 entries is enough to see redaction and costs
    /// milliseconds.
    public static func read(window: TimeInterval = 300, sampleLimit: Int = 200) -> Reading {
        let store: OSLogStore
        do {
            store = try OSLogStore(scope: .system)
        } catch {
            // Deliberately does NOT claim this is a permissions problem. Say what
            // actually happened and let the user judge.
            return Reading(outcome: .storeUnavailable(reason: describe(error)),
                           redactedInSample: 0, sampleSize: 0)
        }

        var entries = 0
        var sampled = 0
        var redacted = 0
        do {
            let seq = try store.getEntries(at: store.position(date: Date().addingTimeInterval(-window)))
            for e in seq {
                entries += 1
                if sampled < sampleLimit {
                    sampled += 1
                    if e.composedMessage.contains("<private>") { redacted += 1 }
                }
                if entries >= 5000 { break }    // hard ceiling; this is a probe
            }
        } catch {
            return Reading(outcome: .storeUnavailable(reason: describe(error)),
                           redactedInSample: redacted, sampleSize: sampled)
        }

        return Reading(
            outcome: entries > 0 ? .readable(entryCount: entries) : .empty,
            redactedInSample: redacted,
            sampleSize: sampled
        )
    }

    /// `OSLogStore` failures are opaque. Classify the ones we can recognise so
    /// the message is specific rather than a generic guess about permissions.
    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileReadNoPermissionError:
                return "not permitted to read the log store (NSFileReadNoPermissionError)"
            case NSFileReadCorruptFileError:
                return "log store reported corrupt (NSFileReadCorruptFileError)"
            default:
                break
            }
        }
        // OSLogError is not public API, so a locked store cannot be matched by
        // name. Report the domain and code verbatim rather than guess.
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }

    /// Message for a source, given a real read result.
    ///
    /// `redactionNote` is appended only when redaction was actually observed, so
    /// the app never tells a user to chase a permission they do not need on a Mac
    /// where nothing was redacted.
    public static func status(for reading: Reading, sourceName: String) -> CapabilityStatus {
        switch reading.outcome {
        case .readable(let n):
            if reading.redactedInSample > 0 {
                let pct = Int((reading.redactionRate * 100).rounded())
                return .available(
                    "Readable (\(n) records). ~\(pct)% of fields are <private>; Full Disk Access unmasks them.")
            }
            return .available("Readable (\(n) records)")

        case .empty:
            // Store opened and answered. No records in the window is a fact
            // about the Mac, not a fault to report.
            return .available("Log store readable; no records in the last 5 minutes")

        case .storeUnavailable(let reason):
            // Name the reason. Do not assert it is a permissions problem unless
            // the error actually says so.
            let permissionish = reason.contains("NSFileReadNoPermissionError")
            return permissionish
                ? .permissionRequired(
                    "Not permitted to read the unified log (\(reason)). Grant Full Disk Access in System Settings → Privacy & Security → Full Disk Access.")
                : .unavailable("Unified log unavailable for \(sourceName): \(reason)")
        }
    }
}