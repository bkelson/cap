#!/bin/bash
# Runs Cap's two logic test harnesses (no Xcode test target exists). Each one compiles every file in Sources/Cap
# except main.swift together with a harness as its own main.swift, then runs it against fake `claude` scripts in a
# throwaway home. Nothing touches your real settings. Takes about 2 minutes (the refresh harness waits ~25 s for timers).
#
#   scripts/run-harness.sh            # both
#   scripts/run-harness.sh model      # welcome-window logic: 37 checks
#   scripts/run-harness.sh refresh    # fetcher / live.json / refresh timing: 22 checks
set -e
cd "$(dirname "$0")/.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
run() {  # $1 = name, $2 = harness file
  echo "== $1"; mkdir -p "$T/$1"; cp "$2" "$T/$1/main.swift"
  swiftc -swift-version 5 -o "$T/$1/t" $(find Sources/Cap -name '*.swift' ! -name main.swift) "$T/$1/main.swift"
  "$T/$1/t" | grep -E "FAIL|ALL PASS|FAILED" || true
}
case "${1:-both}" in
  model)   run model scripts/harness-model.swift ;;
  refresh) run refresh scripts/harness-refresh.swift ;;
  *)       run model scripts/harness-model.swift; run refresh scripts/harness-refresh.swift ;;
esac
