import Foundation

/// A private, numbers-only record of every refresh (when, how long, how many tokens, what it cost, what the
/// limits read), kept in ~/.claude_usage_widget/refresh-log.jsonl so the real cost and reliability of Cap's
/// refreshes can be measured over a day. No account details, no conversation text. Rotated at 2 MB.
enum RefreshLog {
    static let maxBytes = 2_000_000

    static func append(_ entry: [String: Any]) {
        let dir = StatusLineHook.supportDirectory()
        let url = dir.appendingPathComponent("refresh-log.jsonl")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var line = entry
        line["ts"] = Date().timeIntervalSince1970
        line["idle_s"] = Int(UserActivity.secondsIdle)
        line["app_build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        guard var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
            let old = dir.appendingPathComponent("refresh-log.1.jsonl")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}
