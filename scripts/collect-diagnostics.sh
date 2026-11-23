#!/bin/bash
# One-command snapshot of Cap's state for bug reports. Read-only. Contains NO email, org, token or
# conversation content: only yes/no facts, plan names, paths, ages and recent Cap log lines.
#   scripts/collect-diagnostics.sh              prints it
#   scripts/collect-diagnostics.sh > report.txt saves it
APP="/Applications/Cap.app"
echo "=== Cap diagnostics — $(date '+%Y-%m-%d %H:%M:%S')"
echo "macOS $(sw_vers -productVersion) ($(uname -m))"
echo
echo "--- Cap"
if [ -d "$APP" ]; then echo "installed: $APP  v$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $APP/Contents/Info.plist) ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $APP/Contents/Info.plist))"; else echo "NOT in /Applications"; fi
echo "running Cap processes: $(pgrep -u "$(id -u)" -f 'Cap.app/Contents/MacOS/Cap$' | wc -l | tr -d ' ')   (this user's own Cap only; should be 1 while Cap is open)"
echo "quarantine flag on the app: $(xattr "$APP" 2>/dev/null | grep -c quarantine) (1 = it was 'downloaded')"
echo "login item / auto-launch: LaunchAgent plist $([ -f ~/Library/LaunchAgents/ai.kelson.cap.plist ] && echo PRESENT || echo none)"
echo
echo "--- Claude Code"
SA="$HOME/.local/bin/claude"; DESK=$(ls -d "$HOME/Library/Application Support/Claude/claude-code/"*/*/claude.app/Contents/MacOS/claude 2>/dev/null | tail -1)
echo "standalone claude: $([ -x "$SA" ] && echo "found ($("$SA" --version 2>/dev/null | head -1))" || echo none)"
echo "Claude Desktop app: $([ -d /Applications/Claude.app ] && echo installed || echo not installed)"
echo "Desktop's built-in claude: $([ -n "$DESK" ] && echo "found ($("$DESK" --version 2>/dev/null | head -1))" || echo none)"
USE=${SA}; [ -x "$USE" ] || USE="$DESK"
if [ -x "$USE" ]; then
  "$USE" auth status --json 2>/dev/null | python3 -I -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: print('sign-in status: could not be read'); sys.exit()
print('sign-in: loggedIn=%s method=%s plan=%s' % (d.get('loggedIn'), d.get('authMethod'), d.get('subscriptionType')))"
else echo "sign-in: (no claude to ask)"; fi
echo
echo "--- Claude's files Cap relies on"
python3 -I - <<'PY'
import json,os
def load(p):
    try: return json.load(open(os.path.expanduser(p)))
    except FileNotFoundError: return "missing"
    except Exception: return "INVALID JSON"
s=load('~/.claude/settings.json')
if isinstance(s,dict):
    sl=s.get('statusLine'); cmd=(sl or {}).get('command','') if isinstance(sl,dict) else ''
    kind='none' if not sl else ('an older Cap hook (no longer needed)' if '--statusline' in cmd and '/Cap' in cmd else ('old Python hook' if 'statusline.py' in cmd else 'someone else\'s'))
    print("settings.json: valid; statusLine =", kind, "(chained to another command)" if '--then' in cmd else "")
else: print("settings.json:", s)
c=load('~/.claude.json')
if isinstance(c,dict):
    ws=os.path.realpath(os.path.expanduser('~/.claude_usage_widget/feeder_workspace'))
    proj=c.get('projects',{}); p=ws; trusted=False
    while True:
        if (proj.get(p) or {}).get('hasTrustDialogAccepted') is True: trusted=True; break
        n=os.path.dirname(p)
        if n==p: break
        p=n
    print("~/.claude.json: valid; first-run done =", c.get('hasCompletedOnboarding') is True, "; Cap's folder trusted =", trusted)
else: print("~/.claude.json:", c)
PY
echo
echo "--- Data flow"
python3 -I - <<'PY'
import json,os,time
try:
    d=json.load(open(os.path.expanduser('~/.claude_usage_widget/live.json')))
    print("live.json: updated %.0f s ago | session %s%% | week %s%%" % (time.time()-d['updated_at'], d['session_used_pct'], d['week_used_pct']))
except Exception as e: print("live.json: not there yet (", type(e).__name__, ")")
PY
python3 -I - <<'PY'
import json,os,time
try:
    d=json.load(open(os.path.expanduser('~/.claude_usage_widget/refresh-status.json')))
    print("last refresh: %s, %.0f s ago (interval %.0f s)" % (d.get('status'), time.time()-d['at'], d.get('interval_seconds',0)))
except Exception as e: print("last refresh: no status yet (", type(e).__name__, ")")
PY
echo "old hidden sessions still running (should be 0): $(screen -list 2>/dev/null | grep -c claude_usage_feeder)"
echo
echo "--- Cap's own preferences"
defaults read ai.kelson.cap 2>/dev/null | grep -E "hasCompletedOnboarding|isPinned|showInlineMenuBarStats|refreshIntervalSeconds|notificationsEnabled|sessionAlertPercent|weeklyAlertPercent|pinnedLayout|alwaysOnTop" | sed 's/^ */  /' || echo "  (none yet)"
echo
echo "--- Cap's backups of Claude's files (made before every change)"; ls ~/.claude_usage_widget/backups 2>/dev/null | sed 's/^/  /' || echo "  none"
echo
echo "--- Recent Cap log"; tail -12 ~/.claude_usage_widget/widget.log 2>/dev/null | sed 's#/Users/[^/]*/#~/#g' | sed 's/^/  /' || echo "  (empty)"
