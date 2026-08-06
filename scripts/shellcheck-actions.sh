#!/usr/bin/env bash
# Shellchecks every composite action's embedded run: blocks. Complements
# actionlint (which covers .github/workflows/*.yml, including its own
# shellcheck pass on run: steps there) — actionlint doesn't understand the
# action.yml schema, so this is the only coverage those scripts get.
set -euo pipefail

cd "$(dirname "$0")/.."

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

ruby scripts/extract-run-blocks.rb "$tmpdir"

# --severity=warning: only error/warning findings are shown or fail the
# build; info/style are suppressed entirely. The info/style findings this
# hides are known, understood false positives from analyzing extracted
# scripts in isolation — e.g. a Maven ${...} expression that's
# deliberately single-quoted so the shell doesn't touch it, or an env var
# this action sets in its own (unseen-by-shellcheck) env: block — not
# things worth re-litigating on every CI run.
status=0
for script in "$tmpdir"/*.sh; do
  [ -e "$script" ] || continue
  echo "=== $(basename "$script" .sh) ==="
  if ! shellcheck --severity=warning "$script"; then
    status=1
  fi
done

exit "$status"
