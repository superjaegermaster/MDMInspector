import Foundation
import Darwin

/// Resolves the on-disk path of a running process by name using the kernel
/// process list. If the process is not running we return nil — the UI shows
/// "—" rather than a guessed location. No fabricated paths, ever.
public enum ProcessPathResolver {
    private static let cache = NSCache<NSString, NSString>()

    public static func path(forProcessName name: String) -> String? {
        if let cached = cache.object(forKey: name as NSString) { return cached as String }
        guard let path = searchRunningProcesses(matchingLastComponent: name) else { return nil }
        cache.setObject(path as NSString, forKey: name as NSString)
        return path
    }

    /// One pass over the process table, yielding a name → path map.
    ///
    /// Callers that need paths for many records MUST use this instead of
    /// `path(forProcessName:)`: resolving a single name scans the whole
    /// process table, so doing it per record turns an O(n) read into O(n·p).
    public static func pathMap() -> [String: String] {
        var map = [String: String]()
        for (name, path, _) in allProcesses() where map[name] == nil {
            map[name] = path
        }
        return map
    }

    /// All running processes, as (name, path, pid). Used by the inventory source.
    public static func allProcesses() -> [(name: String, path: String, pid: pid_t)] {
        var count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }
        let capacity = Int(count)
        let pids = UnsafeMutablePointer<pid_t>.allocate(capacity: capacity)
        defer { pids.deallocate() }
        count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, pids,
                              Int32(capacity * MemoryLayout<pid_t>.stride))
        guard count > 0 else { return [] }

        var out: [(String, String, pid_t)] = []
        for i in 0..<Int(count) {
            let pid = pids[i]
            guard let path = executablePath(pid: pid) else { continue }
            out.append(((path as NSString).lastPathComponent, path, pid))
        }
        return out
    }

    private static func searchRunningProcesses(matchingLastComponent target: String) -> String? {
        for (name, path, _) in allProcesses() where name == target { return path }
        return nil
    }

    public static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let rc = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard rc > 0 else { return nil }
        return String(cString: buffer)
    }
}
