import Foundation

/// Asks GitHub for Cap's latest release: once at launch if the last check is more than 24 hours old, then once a day.
/// One small request, nothing about the user is sent. Cap never downloads or installs anything itself:
/// "Download" opens the installer's link in the browser.
@MainActor
final class UpdateChecker: ObservableObject {
    /// The GitHub repository that publishes Cap's releases ("owner/name"). Repo not created yet (2026-10-28): checks say "couldn't check" until it is public with a release.
    static let repository = "bkelson/cap"

    static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    @Published private(set) var isChecking = false

    private let preferences: Preferences
    private let fetch: () async throws -> Release
    private var timer: Timer?
    /// Called once per new version, so the app can send its notification.
    var onNewVersion: (String) -> Void = { _ in }

    struct Release: Equatable {
        let version: String
        let releaseURL: String
        let downloadURL: String?
    }

    init(preferences: Preferences, fetch: (() async throws -> Release)? = nil) {
        self.preferences = preferences
        self.fetch = fetch ?? { try await UpdateChecker.fetchLatest() }
    }

    func start() {
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func checkIfDue() {
        guard preferences.checkForUpdatesAutomatically else { return }
        if let last = preferences.lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        check()
    }

    /// "Check now", and the automatic check. Shows "Checking…" until the reply (15 s limit).
    func check() {
        guard !isChecking else { return }
        isChecking = true
        preferences.lastUpdateAttempt = Date()
        Task { @MainActor in
            defer { isChecking = false }
            do {
                let release = try await fetch()
                preferences.lastUpdateCheck = Date()
                preferences.lastUpdateCheckFailed = false
                preferences.latestVersion = release.version
                preferences.latestReleaseURL = release.releaseURL
                preferences.latestDownloadURL = release.downloadURL
                if preferences.updateAvailable, preferences.lastNotifiedVersion != release.version {
                    preferences.lastNotifiedVersion = release.version
                    onNewVersion(release.version)
                }
            } catch {
                preferences.lastUpdateCheckFailed = true
            }
        }
    }

    // MARK: Pure helpers (tested in the harness)

    /// "v1.2.3" or "1.2" to its numbers; nil when it isn't a version.
    static func parts(_ version: String) -> [Int]? {
        var v = version.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        let pieces = v.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !pieces.isEmpty, !pieces.contains(where: { $0 == nil }) else { return nil }
        return pieces.compactMap { $0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parts(candidate), let b = parts(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func parse(_ data: Data) throws -> Release {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        struct Latest: Decodable { let tag_name: String; let html_url: String; let assets: [Asset]? }
        let latest = try JSONDecoder().decode(Latest.self, from: data)
        guard parts(latest.tag_name) != nil else { throw URLError(.cannotParseResponse) }
        let dmg = latest.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }?.browser_download_url
        var version = latest.tag_name
        if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }
        return Release(version: version, releaseURL: latest.html_url, downloadURL: dmg)
    }

    private static func fetchLatest() async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Cap", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parse(data)
    }
}
