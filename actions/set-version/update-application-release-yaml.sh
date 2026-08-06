#!/usr/bin/env bash
# Reads VALIDATED_VERSION and YAML_PATH from the environment. Runs in
# working-directory (set by the calling step).
set -euo pipefail

if [ ! -f "$YAML_PATH" ]; then
  echo "::error::set-version: application-release-yaml-path '$YAML_PATH' does not exist"
  exit 1
fi

export BUILD_UTC
BUILD_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
yq -i '.app.version = strenv(VALIDATED_VERSION) | .app.build = strenv(BUILD_UTC)' "$YAML_PATH"
