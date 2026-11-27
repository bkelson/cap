# Installing Cap

Cap is free and open source. It is signed with an Apple Developer ID and notarized by Apple, so it installs like any other Mac app you download.

## Before you start

- macOS 13 or later, on an Apple silicon Mac (M1 or newer).
- Claude Code or the Claude desktop app, signed in with a **Pro, Max or Ultra** plan.

## Step 1. Download

Download `Cap-<version>.dmg` from [cap.kelson.ai](https://cap.kelson.ai) or the [Releases](../../releases) page.

The first time, Safari may ask whether to allow downloads. Release files are served by GitHub from `release-assets.githubusercontent.com`. Click **Allow**.

## Step 2. Move Cap into Applications

Open the downloaded file and drag **Cap** onto **Applications**.

<img src="assets/install/01-dmg-window.png" width="420" alt="The Cap installer window: the Cap icon on the left, an arrow pointing to the Applications folder on the right, and the words Drag Cap to Applications.">

## Step 3. Open Cap

Open **Cap** from Applications. macOS asks once: “Cap” is an app downloaded from the Internet. Are you sure you want to open it? It adds that Apple checked it for malicious software and none was detected. Click **Open**.

Once Cap is running from Applications, macOS may ask whether to eject the installer disk. Click **Eject** to clear it, or **Not Now** to keep it open. Your downloaded file stays in Downloads either way.

<img src="assets/install/06-eject-installer.png" width="300" alt="A macOS dialog titled Eject the Cap installer? It says Cap is installed and can eject the installer disk, with two buttons: Not Now and Eject.">

Then Cap's welcome window takes it from here.

## Check your download (optional)

- **Fingerprint.** Each release page shows a SHA-256 fingerprint. In Terminal, run `shasum -a 256 ~/Downloads/Cap-<version>.dmg` and compare. If they differ, do not open it.
- **Apple's check.** Run `spctl -a -vv /Applications/Cap.app`. It should say `source=Notarized Developer ID`.
- **The code.** All of it is in this repository, and you can [build it yourself](README.md).

## Other messages you can expect

- **"Cap would like to send you notifications."** This is your choice. Cap uses them for limit alerts and sign-in reminders. You can change it later in Cap's Settings.
- **"Cap can run in the background."** If you turn on "Open Cap at login", macOS tells you about it. That is expected.
- **A Claude sign-in window.** If you are signed out of Claude Code, Cap asks Claude Code to start its normal browser sign-in. You sign in with Claude directly. Cap never sees your password.

<!-- SCREENSHOT STILL NEEDED: notifications prompt, background banner (capture during the clean-user test) -->

## Updates

If you turn on automatic checks, Cap checks GitHub once a day and shows a small red dot on its Settings icon when a new version is out. You can also check by hand at any time. It never installs anything by itself. To update, quit Cap, open the new download, drag **Cap** onto **Applications** and choose **Replace**.

## Something not working?

Open an [issue](../../issues) and say what you saw. Please do not include your Claude login, tokens or conversations. Cap never needs them. To remove Cap, see "Uninstall" in the [README](README.md).
