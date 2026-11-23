import AppKit

/// Two small installer courtesies for the Cap disk image:
///  1. If Cap is started from inside the mounted disk image (not yet dragged to Applications),
///     say so and quit, instead of running from a read-only disk that vanishes on eject.
///  2. Once Cap is installed and running from Applications while the installer disk is still
///     mounted, offer to eject it. The downloaded .dmg is left alone: touching the Downloads folder makes
///     macOS ask for permission, which is a worse trade than leaving one file for the user to delete.
@MainActor
enum InstallerCleanup {
    /// The hidden file the disk image carries so Cap can recognise its own installer disk.
    static let markerName = ".CapInstaller"
    private static let declinedKey = "installerCleanupDeclined"

    static var isRunningFromDiskImage: Bool {
        Bundle.main.bundlePath.hasPrefix("/Volumes/")
    }

    private static var isInstalledInApplications: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    // MARK: 1. Running from the disk image

    static func warnAndQuit() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Drag Cap to your Applications folder first"
        alert.informativeText = "Cap is running from the installer disk. Drag the Cap icon onto the Applications folder in the installer window, then open it from Applications."
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSApp.terminate(nil)
    }

    // MARK: 2. Eject the installer

    /// Finds a mounted Cap installer disk (by its marker file).
    static func findMountedInstaller() -> String? {
        let volumes = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
        return volumes.map { "/Volumes/\($0)" }.first(where: {
            FileManager.default.fileExists(atPath: "\($0)/\(markerName)")
        })
    }

    /// Shows the offer once per installer, only when Cap is installed and the installer disk is still mounted.
    static func offerEjectAndDelete() {
        guard isInstalledInApplications, !UserDefaults.standard.bool(forKey: declinedKey),
              let mountPoint = findMountedInstaller() else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Eject the Cap installer?"
        alert.informativeText = "Cap is installed. I can eject the installer disk. The file you downloaded stays in your Downloads folder, and you can delete it any time."
        alert.addButton(withTitle: "Eject")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: declinedKey)
            return
        }
        eject(mountPoint)
    }

    /// Ejects on a background thread: `hdiutil detach` can take many seconds (it waits for Finder and Spotlight to let go),
    /// and doing it on the main thread froze Cap and held the welcome window back (seen 12 Oct: ~30 s after pressing Eject).
    /// The welcome window now appears straight away; only a failure is reported, afterwards.
    private static func eject(_ mountPoint: String) {
        Task.detached {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint]
            detach.standardOutput = FileHandle.nullDevice
            detach.standardError = FileHandle.nullDevice
            try? detach.run()
            detach.waitUntilExit()
            guard detach.terminationStatus != 0 else { return }
            await MainActor.run {
                let failure = NSAlert()
                failure.messageText = "I couldn't eject the installer"
                failure.informativeText = "Something is still using it. Close any windows showing the installer disk, then eject it from Finder."
                failure.runModal()
            }
        }
    }
}
