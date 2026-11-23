import Foundation

/// Which Claude programs are running at the moment of a refresh. Claude Code keeps one saved login that several programs
/// (the Claude app, a Terminal `claude`, Cap's own refresh) all renew; reports say a renewal can be lost when two of them
/// overlap. This feeds two things: numbers in the refresh log (does a lost login ever coincide with company?) and a short
/// wait before Cap's own refresh when another Claude program is in its busy moment. Nothing here reads a login, a token or
/// any file of Claude's; it only looks at the list of running programs, and only counts leave this file.
enum ProcessProbe {
    struct Snapshot: Equatable {
        /// Running programs named `claude` (Terminal sessions, and the copy the Claude app starts for its Code tab).
        var claudeProcesses: Int
        /// The Claude desktop app itself is open.
        var desktopRunning: Bool
        /// Of those, how many are in a moment when a login renewal is likely: a one-shot headless call (`-p` / `--print`),
        /// or a program that started a few seconds ago. A long-running idle session is NOT counted, or Cap would wait for it forever.
        var busyOthers: Int
    }

    /// A `claude` that started less than this many seconds ago is still starting up (that is when it reads and may renew the login).
    static let youngSeconds = 15

    /// `psOutput` is one program per line: `ps -axo etime=,args=` (elapsed time, then the command line).
    /// Separate from `snapshot` so it can be tested.
    static func parse(_ psOutput: String) -> Snapshot {
        var count = 0, busy = 0
        var desktop = false
        for raw in psOutput.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " ") else { continue }
            let elapsed = seconds(fromElapsed: String(line[..<space]))
            let command = line[line.index(after: space)...].trimmingCharacters(in: .whitespaces)
            // The program is everything before its first flag (a path may contain spaces).
            let parts = command.components(separatedBy: " -")
            let program = parts[0]
            let flags = parts.dropFirst().map { "-" + $0 }
            if program.hasSuffix("/Claude.app/Contents/MacOS/Claude") { desktop = true }
            guard program == "claude" || program.hasSuffix("/claude") else { continue }
            count += 1
            let headless = flags.contains { $0 == "-p" || $0.hasPrefix("-p ") || $0 == "--print" || $0.hasPrefix("--print ") }
            if headless || (elapsed.map { $0 < youngSeconds } ?? false) { busy += 1 }
        }
        return Snapshot(claudeProcesses: count, desktopRunning: desktop, busyOthers: busy)
    }

    /// `ps` elapsed time: `[[dd-]hh:]mm:ss`.
    static func seconds(fromElapsed text: String) -> Int? {
        var rest = text
        var days = 0
        if let dash = rest.firstIndex(of: "-") {
            guard let d = Int(rest[..<dash]) else { return nil }
            days = d
            rest = String(rest[rest.index(after: dash)...])
        }
        let nums = rest.split(separator: ":").map { Int($0) }
        guard !nums.isEmpty, nums.count <= 3, !nums.contains(where: { $0 == nil }) else { return nil }
        let values = nums.map { $0! }
        var total = 0
        for v in values { total = total * 60 + v }
        return days * 86400 + total
    }

    /// Blocking (milliseconds): call off the main thread. Nil if the process list could not be read.
    static func snapshot() -> Snapshot? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "etime=,args="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }
}
