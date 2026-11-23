import Foundation

/// Finds and REMOVES the statusLine hook that older versions of Cap added to ~/.claude/settings.json.
/// Current versions never add anything to Claude's settings; this exists only so a Mac that ran an old version can
/// clean up after it (Settings shows a "Remove" button when a leftover hook is found).
///
/// Safety rules: never touch a settings file that is not valid JSON; always back it up first; keep every other
/// setting; restore the user's own statusLine if the old version had chained it.
struct ClaudeSettingsInstaller {
    let home: URL
    /// Absolute path of Cap's own executable — what the hook runs.
    let hookExecutable: String

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         hookExecutable: String = Bundle.main.executablePath ?? "") {
        self.home = home
        self.hookExecutable = hookExecutable
    }

    enum State: Equatable {
        case notInstalled
        case installed
        /// Cap's hook is present but points at an executable that no longer exists (app moved).
        case needsRepair
        /// The old Python script from development builds.
        case legacy
        /// Someone else's statusLine is set (Cap would chain it).
        case other
    }

    enum InstallError: Error, Equatable {
        case settingsNotValidJSON
        case notWritable(String)
    }

    var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    var supportDirectory: URL { home.appendingPathComponent(".claude_usage_widget", isDirectory: true) }
    private var originalURL: URL { supportDirectory.appendingPathComponent("original_statusline.json") }
    private var backupsDirectory: URL { supportDirectory.appendingPathComponent("backups", isDirectory: true) }

    // MARK: State

    func state() -> State {
        guard let settings = try? readSettings(), let status = settings["statusLine"] as? [String: Any],
              let command = status["command"] as? String else { return .notInstalled }
        if command.contains("--statusline") && command.contains("/Cap") {
            let path = Self.executablePath(in: command)
            return path.map { FileManager.default.isExecutableFile(atPath: $0) } == true ? .installed : .needsRepair
        }
        if command.contains("claude_usage_widget") && command.contains("statusline.py") { return .legacy }
        return .other
    }

    // MARK: Install / uninstall

    /// Removes Cap's hook, restoring the user's original statusLine if there was one.
    func uninstall() throws {
        var settings = try readSettings()
        guard settings["statusLine"] != nil else { return }
        _ = try backupSettings()
        if let data = try? Data(contentsOf: originalURL),
           let original = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings["statusLine"] = original
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try writeSettings(settings)
        try? FileManager.default.removeItem(at: originalURL)
    }

    // MARK: Files

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.settingsNotValidJSON
        }
        return object
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existingPermissions = (try? FileManager.default.attributesOfItem(atPath: settingsURL.path)[.posixPermissions]) as? NSNumber
        do { try writeJSON(settings, to: settingsURL) }
        catch { throw InstallError.notWritable(settingsURL.path) }
        if let existingPermissions {
            try? FileManager.default.setAttributes([.posixPermissions: existingPermissions], ofItemAtPath: settingsURL.path)
        }
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    /// Copies the current settings.json into Cap's backups folder (nil if there is none yet).
    private func backupSettings() throws -> URL? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let stamp = fmt.string(from: Date())
        // Two backups in the same millisecond must not collide (or the install would fail).
        var url = backupsDirectory.appendingPathComponent("settings-\(stamp).json")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = backupsDirectory.appendingPathComponent("settings-\(stamp)-\(n).json")
            n += 1
        }
        try FileManager.default.copyItem(at: settingsURL, to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    // MARK: Shell quoting

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The executable inside `'/path/with spaces/Cap' --statusline …`.
    static func executablePath(in command: String) -> String? {
        guard command.first == "'", let end = command.dropFirst().firstIndex(of: "'") else {
            return command.split(separator: " ").first.map(String.init)
        }
        return String(command[command.index(after: command.startIndex)..<end])
    }
}
