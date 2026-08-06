#!/usr/bin/env bash
# Shellchecks every composite action's script files directly. Complements
# actionlint (which covers .github/workflows/*.yml, including its own
# shellcheck pass on run: steps there) — actionlint doesn't understand the
# action.yml schema, so scripts referenced from actions/*/action.yml via
# ${{ github.action_path }}/name.sh get no coverage from it otherwise.
set -euo pipefail

cd "$(dirname "$0")/.."

# --severity=warning: only error/warning findings are shown or fail the
# build; info/style are suppressed entirely — not things worth blocking
# on, and any genuinely useful ones can be promoted case by case.
status=0
for script in actions/*/*.sh; do
  [ -e "$script" ] || continue
  echo "=== $script ==="
  if ! shellcheck --severity=warning "$script"; then
    status=1
  fi
done

exit "$status"
