import Foundation

/// Finds the Claude Code command-line program. launchd gives apps a minimal
/// PATH, so a bare `claude` is not found when Cap starts at login — look in
/// the usual install locations first, then ask the user's login shell.
enum ClaudeLocator {
    struct Found: Equatable {
        let path: String
        let version: String?
        /// True when this is the copy of Claude Code built into the Claude Desktop app.
        var isDesktopBundle = false
    }

    /// `withVersion: false` skips running `claude --version` (can take a moment); `askShell: false`
    /// skips the login-shell fallback, which can block for a few seconds.
    ///
    /// `preferNewest: true` (what runs Cap's refreshes and sign-ins): when the copy built into the Claude app is a newer
    /// version than the standalone install, use that one. Claude Code 2.1.317 and 2.1.318 fixed several ways a call could be
    /// cut off before saving a renewed login (`claude auth status`, plugin commands) and 2.1.318 added the date the sign-in
    /// ends, which is what lets Cap warn before it lapses. A standalone install that nobody has updated (2.1.306 on the
    /// development Mac) has none of that. The version is read from the install path (native installs and the app's copy
    /// both keep it in a folder name), so nothing has to be run to compare.
    static func find(home: URL = FileManager.default.homeDirectoryForCurrentUser, askShell: Bool = true, withVersion: Bool = true,
                     preferNewest: Bool = false) -> Found? {
        let h = home.path
        let candidates = [
            "\(h)/.local/bin/claude",
            "\(h)/.claude/local/claude",
            "\(h)/.npm-global/bin/claude",
            "\(h)/.bun/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            if preferNewest, let bundled = desktopBundledClaude(home: home),
               let have = versionFromPath(path), let offered = versionFromPath(bundled), isNewer(offered, than: have) {
                return Found(path: bundled, version: withVersion ? version(of: bundled) : nil, isDesktopBundle: true)
            }
            return Found(path: path, version: withVersion ? version(of: path) : nil)
        }
        // No standalone install: use the Claude Code built into the Claude Desktop app
        // (what "Get Claude for Mac" installs).
        if let path = desktopBundledClaude(home: home) {
            return Found(path: path, version: withVersion ? version(of: path) : nil, isDesktopBundle: true)
        }
        guard askShell,
              let out = run("/bin/zsh", ["-lc", "command -v claude"], timeout: 5),
              let line = out.split(separator: "\n").last.map(String.init),
              line.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: line) else { return nil }
        return Found(path: line, version: withVersion ? version(of: line) : nil)
    }

    /// Is the Claude app itself installed? Its built-in Claude Code is only downloaded the first
    /// time the Code feature is used, so the app can be here while the built-in copy is not.
    static func desktopAppInstalled(in applicationFolders: [URL]) -> Bool {
        applicationFolders.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Claude.app").path) }
    }

    /// `~/Library/Application Support/Claude/claude-code/<version>/<id>/claude.app/Contents/MacOS/claude`.
    /// An unofficial location that changes with each Claude Desktop update, so the newest
    /// version is picked every time rather than remembered.
    static func desktopBundledClaude(home: URL) -> String? {
        let root = home.appendingPathComponent("Library/Application Support/Claude/claude-code", isDirectory: true)
        let fm = FileManager.default
        guard let versions = try? fm.contentsOfDirectory(atPath: root.path) else { return nil }

        func key(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0) ?? 0 } }
        let newestFirst = versions.sorted { a, b in
            let (ka, kb) = (key(a), key(b))
            for i in 0..<max(ka.count, kb.count) {
                let (x, y) = (i < ka.count ? ka[i] : 0, i < kb.count ? kb[i] : 0)
                if x != y { return x > y }
            }
            return false
        }
        for version in newestFirst {
            let versionDir = root.appendingPathComponent(version, isDirectory: true)
            guard let ids = try? fm.contentsOfDirectory(atPath: versionDir.path) else { continue }
            let executables = ids
                .map { versionDir.appendingPathComponent($0).appendingPathComponent("claude.app/Contents/MacOS/claude").path }
                .filter { fm.isExecutableFile(atPath: $0) }
            if let best = executables.max(by: { modified($0) < modified($1) }) { return best }
        }
        return nil
    }

    /// "2.1.306" read from the real location of the program (symlinks followed): the first folder name on the way up
    /// that looks like a version. Nil when there is none (an npm or Homebrew install), in which case Cap leaves the
    /// standalone copy alone.
    static func versionFromPath(_ path: String) -> [Int]? {
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        for part in real.pathComponents.reversed() {
            let pieces = part.split(separator: ".", omittingEmptySubsequences: false)
            if pieces.count == 3, let a = Int(pieces[0]), let b = Int(pieces[1]), let c = Int(pieces[2]) { return [a, b, c] }
        }
        return nil
    }

    static func isNewer(_ a: [Int], than b: [Int]) -> Bool {
        for i in 0..<max(a.count, b.count) {
            let (x, y) = (i < a.count ? a[i] : 0, i < b.count ? b[i] : 0)
            if x != y { return x > y }
        }
        return false
    }

    private static func modified(_ path: String) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date) ?? .distantPast
    }

    static func version(of path: String) -> String? {
        run(path, ["--version"], timeout: 5)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs a program and returns stdout, or nil on failure or timeout.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval, environment: [String: String]? = nil) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        if let environment { task.environment = environment }
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let deadline = ClaudeRun.uptime() + timeout    // awake time, so a sleep mid-call can't trip it
        while task.isRunning && ClaudeRun.uptime() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if task.isRunning { task.terminate(); return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
