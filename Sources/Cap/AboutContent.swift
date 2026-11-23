import AppKit
import SwiftUI

/// Content of the About window (replaces the standard macOS About panel, 2026-10-30).
enum AboutContent {
    /// "Email me": opens the user's mail app with a new message to this address.
    static let emailURL = URL(string: "mailto:brian@kelson.ai")!

    /// "Buy me coffee": the GitHub Sponsors page. `nil` until sponsorship is approved; while it is `nil` the line is not shown.
    /// To switch it on, set this to the approved page (for example `URL(string: "https://github.com/sponsors/bkelson")`).
    static let sponsorURL: URL? = nil

    /// The official logo: tagline lockup, solid, light (LOGO.md, locked 2026-10-30). Shipped in the app's Resources.
    static let logoFileName = "cap-logo-tagline-solid-light-1600"

    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    static func logoImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: logoFileName, withExtension: "png"), let image = NSImage(contentsOf: url) { return image }
        #if CAP_TEST_BUILD
        // Running the bare test binary (not an app bundle): look in the project's assets folder.
        let path = FileManager.default.currentDirectoryPath + "/assets/Logo/\(logoFileName).png"
        if let image = NSImage(contentsOfFile: path) { return image }
        #endif
        return nil
    }
}

/// The About window: logo, a line to write to me, (later) a coffee line, and the sign-off.
struct AboutView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 18) {
            logo
            Text(AboutContent.versionLine)
                .font(.system(size: 11))
                .foregroundStyle(Brand.muted(scheme))
            VStack(spacing: 8) {
                Text(sentence("Found a bug or want to say hello? ", link: "Email me", url: AboutContent.emailURL))
                if let sponsor = AboutContent.sponsorURL {
                    Text(sentence("Appreciate my work? ", link: "Buy me coffee", url: sponsor))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Brand.ink(scheme))
            .tint(scheme == .dark ? Color(red: 0.85, green: 0.45, blue: 0.30) : Color(red: 0.71, green: 0.33, blue: 0.18))   // button/primary
            .multilineTextAlignment(.center)
            Text("Made with ♥ for the Claude community.")
                .font(.system(size: 11.5))
                .foregroundStyle(Brand.muted(scheme))
                .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .padding(.top, 26)
        .padding(.bottom, 26)
        .frame(width: 380)
        .background(Brand.surface(scheme))
    }

    @ViewBuilder private var logo: some View {
        if let image = AboutContent.logoImage() {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 280)
                .accessibilityLabel("Cap, a usage tracker thingy for Claude")
        } else {
            Text("Cap").font(.system(size: 34, weight: .semibold)).foregroundStyle(Brand.terracotta)   // only if the logo file is missing
        }
    }

    /// "lead" followed by a link and a full stop.
    private func sentence(_ lead: String, link: String, url: URL) -> AttributedString {
        var text = AttributedString(lead)
        var linked = AttributedString(link)
        linked.link = url
        linked.underlineStyle = .single
        text.append(linked)
        text.append(AttributedString("."))
        return text
    }
}
