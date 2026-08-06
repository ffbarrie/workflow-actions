#!/usr/bin/env bash
# Reads LANGUAGE, VERSION, TAG_PREFIX, BRANCH from the environment (set by
# the calling step's env: block) and writes success/error-message/
# validated-version to $GITHUB_OUTPUT. See action.yml's description for
# the full comparison/dev-suffix rules.

fail() {
  echo "::error::set-version: $1" >&2
  echo "success=false" >> "$GITHUB_OUTPUT"
  echo "error-message=$1" >> "$GITHUB_OUTPUT"
  echo "validated-version=" >> "$GITHUB_OUTPUT"
  exit 1
}

version_gt() {
  # returns success (0) if $1 is strictly greater than $2, both X.Y.Z
  IFS='.' read -r a1 a2 a3 <<< "$1"
  IFS='.' read -r b1 b2 b3 <<< "$2"
  if (( 10#$a1 != 10#$b1 )); then (( 10#$a1 > 10#$b1 )); return; fi
  if (( 10#$a2 != 10#$b2 )); then (( 10#$a2 > 10#$b2 )); return; fi
  (( 10#$a3 > 10#$b3 ))
}

if [ "$LANGUAGE" != "node" ] && [ "$LANGUAGE" != "java" ]; then
  fail "language must be 'node' or 'java', got '$LANGUAGE'"
fi

version="${VERSION#v}"
version="${version#V}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "version '$VERSION' is not a valid X.Y.Z semantic version"
fi

dev_suffix=""
if [ "$BRANCH" = "develop" ]; then
  case "$LANGUAGE" in
    java) dev_suffix="-SNAPSHOT" ;;
    node) dev_suffix="-dev" ;;
  esac
fi

if [ "$BRANCH" = "develop" ] || [ "$BRANCH" = "main" ]; then
  closest_tag=$(git describe --tags --abbrev=0 --match "${TAG_PREFIX}[0-9]*.[0-9]*.[0-9]*" 2>/dev/null || true)
  if [ -n "$closest_tag" ]; then
    closest_version="${closest_tag#"$TAG_PREFIX"}"
    if [ -n "$dev_suffix" ]; then
      # develop: the next dev version may legitimately equal the
      # closest tag (e.g. right after a release resync, tag v1.1.0
      # and the version file both read 1.1.0) — only regressing
      # below it is invalid.
      if version_gt "$closest_version" "$version"; then
        fail "version $version is less than $closest_tag, the closest existing release tag on $BRANCH"
      fi
    elif ! version_gt "$version" "$closest_version"; then
      fail "version $version is not greater than $closest_tag, the closest existing release tag on $BRANCH"
    fi
  fi
fi

final_version="${version}${dev_suffix}"

echo "success=true" >> "$GITHUB_OUTPUT"
echo "error-message=" >> "$GITHUB_OUTPUT"
echo "validated-version=$final_version" >> "$GITHUB_OUTPUT"
