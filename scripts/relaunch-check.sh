#!/bin/bash
# Launch check: Cap must STAY RUNNING when it starts with setup already finished (the case every normal day).
# Build 25/26 crashed here (menu bar item installed before the popover existed) and no test caught it, because the
# first-run tests never relaunch. Run this before every installer:   scripts/relaunch-check.sh
# It runs the debug build against a throwaway HOME (no real Claude, no real data) and a throwaway settings domain.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build 2>&1 | tail -1
T="$(mktemp -d)"; mkdir -p "$T/home"
defaults write Cap hasCompletedOnboarding -bool true
trap 'defaults delete Cap hasCompletedOnboarding 2>/dev/null || true; kill "${PID:-0}" 2>/dev/null || true; rm -rf "$T"' EXIT
HOME="$T/home" .build/debug/Cap > "$T/out.log" 2>&1 & PID=$!
sleep 6
if kill -0 "$PID" 2>/dev/null; then echo "PASS  Cap stays running after launching with setup finished"; exit 0
else echo "FAIL  Cap exited at launch with setup finished:"; tail -3 "$T/out.log"; exit 1; fi
