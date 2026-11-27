# Frequently asked questions

## About Cap

**Why does Cap exist?**

Cap started as a learning project. Its first goal was to understand how Claude's usage works and to make it visible. That's still the core of it. We've since decided to see how far it can go as a useful tool, and to be clear about what it does and doesn't do.

At its heart, Cap is about helping Claude users make better-informed decisions. That means understanding both the financial and environmental costs of their work, and building a habit of using Claude more thoughtfully and efficiently.

**Claude already shows usage in the menu bar. Why do I need Cap?**

Claude's own menu bar item shows your session and weekly usage, and we think that's a useful step. As of 4 November 2026, Claude's settings don't include alerts at a percentage you choose, or a desktop widget. Cap offers both.

Cap also doesn't need your Claude login. Some other tools ask for a session key from your browser or store your credentials. Cap reads the usage figures that Claude Code reports, and nothing more.

Cap is version 1, and it's the first step in a bigger project. That project is about helping people see the wider set of costs that come with working in Claude, not only the plan limits.

**Who can use Cap?**

People on a Claude Pro, Max or Ultra plan (Ultra is the plan that used to be called Max 20x), using Claude Code or the Claude desktop app, on an Apple silicon Mac running macOS 13 or later.

**Is Cap made by Anthropic?**

No. Cap is an independent project and is not made or endorsed by Anthropic. "Claude" is a trademark of Anthropic.

## Installing

**Will macOS warn me when I open Cap?**

Only with its usual question for any app downloaded from the internet. Click **Open**. Since version 1.0.1, Cap is signed with an Apple Developer ID and notarized by Apple.

**Is it safe to open?**

Apple's notary service has scanned it for known malware, which is not a review of what the app does. Every release has a SHA-256 fingerprint on its release page. You can check your download against it in Terminal before you open it. You can also read all of the code, or build Cap yourself.

**How do I update?**

Quit Cap, open the new download, drag **Cap** onto **Applications** and choose **Replace**.

## Using Cap

**Does Cap use up my usage?**

Each check is a very small request, so its cost to your plan is negligible. Cap checks every 15 seconds while you're at your Mac and pauses when you're away. There's no setting for this.

**Will I have to sign in again?**

About once a month. Cap reads your numbers through your own Claude Code sign-in, and Claude Code sign-ins last about 28 to 30 days. A week before yours ends, Cap shows a "Renew sign-in" button in its popover and sends a notification, and another two days before. Renewing takes one browser approval, about a minute. If your Claude Code is older than version 2.1.318, Cap can't read the end date, so it can only tell you after the sign-in has ended. Update Claude Code to get the warning.

**Why does Cap say it can't find Claude?**

Cap reads its numbers through Claude Code. Install Claude Code or the Claude desktop app, and Cap will pick it up within a minute.

**Are the numbers the same as on claude.ai or my bill?**

Cap shows the usage figures that Claude Code reports. It isn't a billing tool, so the figures can differ from your bill.

**How do I get updates?**

If you turn on "Check for updates automatically" in Settings, Updates, Cap checks GitHub once a day. If there's a new version, a red dot appears on the Settings icon. It's off until you choose to turn it on. You can also check by hand at any time. Download opens the release page in your browser. Cap never installs anything on its own.

**How do I remove Cap?**

Quit Cap, then drag it from Applications to the Trash. If you also want to remove what Cap saved, see the Uninstall section of the [README](README.md).

## Privacy

**What data does Cap collect or send?**

Cap has no account and no analytics. It doesn't send your usage figures or account details anywhere. The only request Cap makes itself is the daily update check to GitHub, and only if you turn that on. [PRIVACY.md](PRIVACY.md) lists exactly what Cap reads, writes and sends.

## Help

**How do I report a problem or suggest something?**

Open an issue on GitHub, or [email Brian](mailto:brian@kelson.ai). Please don't include your Claude login, tokens or conversations. Cap never needs them.
