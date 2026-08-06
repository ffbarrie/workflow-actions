#!/usr/bin/env bash
# Reads LANGUAGE from the environment. Runs in working-directory (set by
# the calling step). Writes version/base-version/is-snapshot to
# $GITHUB_OUTPUT.
set -euo pipefail

if [ "$LANGUAGE" != "node" ] && [ "$LANGUAGE" != "java" ]; then
  echo "::error::get-version: language must be 'node' or 'java', got '$LANGUAGE'"
  exit 1
fi

if [ "$LANGUAGE" = "node" ]; then
  version=$(node -p "require('./package.json').version")
  dev_suffix="-dev"
else
  version=$(mvn -B -q -Dexec.executable=echo -Dexec.args='${project.version}' \
    org.codehaus.mojo:exec-maven-plugin:3.1.0:exec)
  dev_suffix="-SNAPSHOT"
fi

base_version="${version%"$dev_suffix"}"
is_snapshot=false
if [ "$base_version" != "$version" ]; then
  is_snapshot=true
fi

echo "version=$version" >> "$GITHUB_OUTPUT"
echo "base-version=$base_version" >> "$GITHUB_OUTPUT"
echo "is-snapshot=$is_snapshot" >> "$GITHUB_OUTPUT"
