# What Cap reads, writes and sends

Short version: today Cap works with what is already on your Mac. It has no account system and no analytics. If that ever changes, this page will say so first, and the change will be off until you turn it on.

## What Cap reads

- **Usage figures** from the copy of Claude Code on your Mac: the percentages used and reset times for your 5-hour session and weekly limit, read from the output of a short `claude -p` run.
- **Whether you are signed in**, by asking Claude Code (`claude auth status`). Cap learns "yes" or "no" and your plan name. It does not read your login token.
- **Where Claude Code lives** on your Mac, and whether Claude programs are running (names of processes only), so Cap does not collide with a refresh you are running yourself.
- **macOS settings**: whether macOS lets Cap send notifications, your Icon & widget style (for the widget's look), and whether you are at the Mac (to pause while you are away).

## What Cap does **not** do

- It does not read, ask for, copy or store your password, your login token, or anything in your Keychain.
- It does not edit Claude's settings (older versions added a status hook; Settings offers to remove it if it is still there).
- Today, Cap sends no usage data, identifiers or analytics. The only request Cap makes on its own is the update check, which is off until you turn it on.

## What Cap writes (all on your Mac)

- `~/.claude_usage_widget/` holds the latest readings (`live.json`), a log of refreshes (numbers and timings only, no content), a small working folder for the one-word request, and backups of those files.
- Your settings (layout, alerts, thresholds) are saved by macOS in the `ai.kelson.cap` preferences.
- An optional login item, only if you turn on "Open Cap at login" (it starts off).

## What Cap sends over the internet

- **Cap itself** makes one request, and only if you turn on "Check for updates automatically" in Settings, Updates. It's off until you choose to turn it on. When it's on, Cap asks `api.github.com` once a day (and at launch if a day has passed) for the latest Cap release. GitHub sees your IP address and the name "Cap", like any web request.
- **Claude Code** talks to Anthropic as it always does when Cap asks it for the figures. That traffic is between Claude Code and Anthropic.

## Sign-in

If you are signed out, Cap can start Claude Code's own sign-in (`claude auth login`). It opens your browser; you sign in with Claude directly. Cap never sees what you type.

## Check it yourself

Cap is open source. The places to look are `Sources/Cap/UsageFetcher.swift` (the refresh), `ClaudeAuth.swift` and `ActiveSignIn.swift` (sign-in), `UpdateChecker.swift` (the only network call Cap makes itself) and `RefreshLog.swift` (what is logged).
