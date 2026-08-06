#!/usr/bin/env bash
# Reads VALIDATED_VERSION from the environment. Runs in working-directory
# (set by the calling step).
set -euo pipefail

npm version "$VALIDATED_VERSION" --no-git-tag-version --allow-same-version

# Lockstep, not independent: every non-private package under packages/
# gets forced to the same version as root, matching real-world precedent
# (Foundry-Innovations-PBC/foundry-client's sync-workspace-versions.mjs)
# and the lesson already recorded in build-test-node-library.yml's header
# comment — an earlier release workflow broke production by versioning
# workspace packages independently instead of atomically. Internal
# @scope/* dependency ranges are assumed to already be workspace:*/range
# (not exact-pinned), so no dependency-string rewriting is needed here —
# only each package's own version field.
for pkg_json in packages/*/package.json; do
  [ -f "$pkg_json" ] || continue
  is_private=$(node -p "require('./${pkg_json}').private === true")
  if [ "$is_private" = "true" ]; then
    continue
  fi
  ( cd "$(dirname "$pkg_json")" && npm version "$VALIDATED_VERSION" --no-git-tag-version --allow-same-version )
done
