import AppKit
import Darwin
import OSLog

/// A group of background processes sharing one installation: a CLI tool or
/// daemon with no Dock icon, no menu bar item and no `NSRunningApplication`.
struct BackgroundProcess: Identifiable, Hashable {
    /// What the blacklist stores: the installation root for tools with several
    /// binaries, or the executable path for everything else.
    let id: String
    let name: String
    let pids: [Int32]
    /// Every executable in the group, for display and for the pre-kill safety check.
    let executablePaths: [String]
    /// Start time of the oldest process in the group.
    let startedAt: Date

    var processCount: Int { pids.count }

    /// Where the tool lives, shortened with `~` when it sits in the home folder.
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if id.hasPrefix(home + "/") {
            return "~" + id.dropFirst(home.count)
        }
        return id
    }

    func matches(_ path: String) -> Bool {
        executablePaths.contains(path)
    }
}

/// One scan of the process table.
struct ProcessScanResult {
    /// Groups that can be listed and stopped.
    let groups: [BackgroundProcess]
    /// Groups skipped only because SwiftQuit is running inside them. They are
    /// normally stoppable; the exception exists so clean-up can never take down
    /// the terminal session that launched the app.
    let ancestorGroups: [BackgroundProcess]
}

/// Scans the BSD process table for background work the user may want to stop in
/// bulk: homebrew services, daemons, build watchers and other CLI processes.
///
/// This is deliberately not `NSWorkspace.runningApplications`, which only knows
/// about GUI apps and therefore never sees tools such as `herdr` or `opencode`.
enum ProcessScanner {
    private static let logger = Logger(subsystem: "com.swiftquit.SwiftQuit", category: "ProcessScanner")

    /// Paths that always belong to the OS or to Apple tooling.
    private static let systemPrefixes = [
        "/System/",
        "/usr/libexec/",
        "/usr/sbin/",
        "/usr/bin/",
        "/usr/lib/",
        "/bin/",
        "/sbin/",
        "/Library/Apple/",
        "/Library/Developer/",
        "/dev/",
    ]

    /// Homebrew keeps every version of a formula under these roots. Grouping by
    /// formula means `container` shows up once instead of as five helper binaries.
    private static let homebrewRoots = [
        "/opt/homebrew/Cellar/",
        "/usr/local/Cellar/",
    ]

    /// Processes younger than this are usually transient build steps, helper
    /// invocations or one-shot commands, so listing them would just flicker.
    private static let minimumAge: TimeInterval = 30

    static func scan() -> ProcessScanResult {
        let protected = protectedPIDs()
        let uid = getuid()
        let now = Date()

        struct Bucket {
            var key: String
            var name: String
            var pids: [Int32] = []
            var paths: Set<String> = []
            var startedAt: Date
            /// True when every process in the group is an ancestor of SwiftQuit.
            var allProtected = true
        }

        var buckets: [String: Bucket] = [:]

        for record in allProcesses() {
            let pid = record.pid
            guard pid > 0, pid != getpid() else { continue }
            guard record.uid == uid else { continue }
            guard record.status != UInt32(SZOMB) else { continue }

            let path = record.path
            guard !path.isEmpty else { continue }
            // Helpers that live inside an app bundle belong to that app and are
            // closed together with it.
            guard !path.contains(".app/Contents/") else { continue }
            guard !systemPrefixes.contains(where: { path.hasPrefix($0) }) else { continue }

            let age = now.timeIntervalSince(record.startedAt)
            guard age >= minimumAge else { continue }

            let (key, name) = identity(for: path)
            let isAncestor = protected.contains(pid)

            if var bucket = buckets[key] {
                bucket.pids.append(pid)
                bucket.paths.insert(path)
                if record.startedAt < bucket.startedAt { bucket.startedAt = record.startedAt }
                if !isAncestor { bucket.allProtected = false }
                buckets[key] = bucket
            } else {
                buckets[key] = Bucket(
                    key: key,
                    name: name,
                    pids: [pid],
                    paths: [path],
                    startedAt: record.startedAt,
                    allProtected: isAncestor
                )
            }
        }

        var groups: [BackgroundProcess] = []
        var ancestors: [BackgroundProcess] = []
        for bucket in buckets.values {
            let process = BackgroundProcess(
                id: bucket.key,
                name: bucket.name,
                pids: bucket.pids.sorted(),
                executablePaths: bucket.paths.sorted(),
                startedAt: bucket.startedAt
            )
            if bucket.allProtected {
                ancestors.append(process)
            } else {
                groups.append(process)
            }
        }

        func sorted(_ list: [BackgroundProcess]) -> [BackgroundProcess] {
            list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return ProcessScanResult(groups: sorted(groups), ancestorGroups: sorted(ancestors))
    }

    /// Decides how a process is grouped and named.
    ///
    /// Homebrew formulae are grouped per formula, so the five `container-*`
    /// helpers become one "container" row that stops the whole service. Anything
    /// else is grouped per executable, which keeps unrelated users of the same
    /// runtime (say two `java` daemons) independently controllable.
    private static func identity(for path: String) -> (key: String, name: String) {
        for root in homebrewRoots where path.hasPrefix(root) {
            let remainder = path.dropFirst(root.count)
            guard let formula = remainder.split(separator: "/").first, !formula.isEmpty else { break }
            return (root + formula, String(formula))
        }
        let name = (path as NSString).lastPathComponent
        return (path, name)
    }

    /// SwiftQuit itself and every process it descends from. Killing an ancestor
    /// would take down the terminal session the app was launched from (for
    /// example `herdr` or `opencode` when started from a shell).
    static func protectedPIDs() -> Set<Int32> {
        var result: Set<Int32> = [1]
        var current = getpid()
        while current > 1 {
            result.insert(current)
            guard let info = bsdInfo(current) else { break }
            let parent = Int32(bitPattern: info.pbi_ppid)
            guard parent != current else { break }
            current = parent
        }
        return result
    }

    /// Sends SIGTERM, waits for the group to exit, then SIGKILLs stragglers.
    ///
    /// Only processes whose executable still belongs to the group are signalled,
    /// and ancestors of this process are re-checked here, so a reused PID or a
    /// stale snapshot can never take down the wrong thing.
    static func terminate(_ group: BackgroundProcess, gracePeriod: TimeInterval = 3) async -> Bool {
        let protected = protectedPIDs()
        let targets = group.pids.filter { pid in
            guard !protected.contains(pid) else { return false }
            guard let path = executablePath(pid) else { return false }
            return group.matches(path) || path.hasPrefix(group.id + "/")
        }
        guard !targets.isEmpty else { return true }

        for pid in targets {
            kill(pid, SIGTERM)
        }

        if await waitUntilExited(targets, timeout: gracePeriod) { return true }

        let survivors = targets.filter { isRunning($0) }
        for pid in survivors {
            kill(pid, SIGKILL)
        }

        if await waitUntilExited(survivors, timeout: 2) { return true }

        let stubborn = survivors.filter { isRunning($0) }
        if !stubborn.isEmpty {
            logger.debug("\(group.name, privacy: .public) still running: \(stubborn.description, privacy: .public)")
        }
        return stubborn.isEmpty
    }

    private static func waitUntilExited(_ pids: [Int32], timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pids.allSatisfy({ !isRunning($0) }) { return true }
            try? await Task.sleep(for: .milliseconds(120))
        }
        return pids.allSatisfy { !isRunning($0) }
    }

    // MARK: - Process table

    private struct ProcessRecord {
        let pid: Int32
        let uid: uid_t
        let status: UInt32
        let path: String
        let startedAt: Date
    }

    private static func allProcesses() -> [ProcessRecord] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        // The table can grow between the size probe and the fetch, so retry with
        // extra headroom instead of silently truncating the list.
        for _ in 0..<3 {
            let capacity = size / MemoryLayout<kinfo_proc>.stride + 32
            var procs = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            var actualSize = capacity * MemoryLayout<kinfo_proc>.stride
            if sysctl(&mib, 3, &procs, &actualSize, nil, 0) == 0 {
                let count = min(capacity, actualSize / MemoryLayout<kinfo_proc>.stride)
                return procs.prefix(count).compactMap { record(from: $0) }
            }
            size = actualSize
        }
        return []
    }

    private static func record(from kinfo: kinfo_proc) -> ProcessRecord? {
        let pid = kinfo.kp_proc.p_pid
        guard pid > 0, let info = bsdInfo(pid) else { return nil }
        guard let path = executablePath(pid) else { return nil }
        return ProcessRecord(
            pid: pid,
            uid: info.pbi_uid,
            status: info.pbi_status,
            path: path,
            startedAt: Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
        )
    }

    private static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        return result == size ? info : nil
    }

    private static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * 1024)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func isRunning(_ pid: Int32) -> Bool {
        guard let info = bsdInfo(pid) else { return false }
        return info.pbi_status != UInt32(SZOMB)
    }
}
