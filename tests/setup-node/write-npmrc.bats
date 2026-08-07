#!/usr/bin/env bats
# Covers actions/setup-node/write-npmrc.sh — content should round-trip
# to ~/.npmrc exactly, since NPMRC often carries auth tokens where an
# unexpected added/stripped newline or truncation would be a real bug.

SCRIPT="$BATS_TEST_DIRNAME/../../actions/setup-node/write-npmrc.sh"

setup() {
  HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export HOME
}

@test "single-line content is written verbatim" {
  NPMRC="registry=https://registry.npmjs.org" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.npmrc")" = "registry=https://registry.npmjs.org" ]
}

@test "multi-line content (multiple registries/scopes) is preserved exactly" {
  content=$'@myorg:registry=https://npm.pkg.github.com\n//npm.pkg.github.com/:_authToken=abc123\nregistry=https://registry.npmjs.org'
  NPMRC="$content" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.npmrc")" = "$content" ]
}

@test "overwrites any existing ~/.npmrc rather than appending" {
  echo "stale=content" > "$HOME/.npmrc"
  NPMRC="fresh=content" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.npmrc")" = "fresh=content" ]
}
