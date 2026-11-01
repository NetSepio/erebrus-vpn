#!/usr/bin/env bash
# Runs a CI build command and, if it fails, repeats its error lines as
# workflow annotations. Annotations are public through the GitHub API, while
# step logs need a signed-in account, so failures stay diagnosable.
#
# Usage: scripts/ci-annotate.sh <command> [args...]
set -uo pipefail

log="$(mktemp)"
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

annotate() {
  local text="$1"
  text="${text//'%'/%25}"
  text="${text//$'\r'/}"
  text="${text//$'\n'/%0A}"
  printf '::error title=%s::%s\n' "$2" "${text:0:4000}"
}

if [[ "$status" -ne 0 ]]; then
  # Xcode names the failing command on the line after "failed with exit
  # code", and lists failed commands under "The following build commands
  # failed:", so those lines are kept with their context; flutter's iOS build
  # summarizes Xcode issues as "<kind> (Xcode): ...". GitHub shows at most 10
  # error annotations per step, so the summary goes in one annotation.
  summary="$(awk '
    /The following build commands failed:/ { block = 8 }
    /failed with exit code [1-9]|failed with a nonzero exit code/ { print; ctx = 2; next }
    /\(Xcode\): / { print; next }
    block > 0 { print; block--; next }
    ctx > 0 { print; ctx--; next }
  ' "$log" | tail -n 40)"
  [[ -n "$summary" ]] && annotate "$summary" "$1: failed build commands"

  grep -E '(^|[^A-Za-z])(error|Error|ERROR|fatal|FAILED|Exception)([: ]|$)' "$log" |
    grep -v '^::' | grep -v 'failed with exit code 0' | tail -n 8 |
    while IFS= read -r line; do
      annotate "${line:0:500}" "$1 failed"
    done
fi
rm -f "$log"
exit "$status"
