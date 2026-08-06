#!/usr/bin/env bats
# Covers the comparison/dev-suffix logic in
# actions/set-version/validate-version.sh — the most complex, most
# bug-prone script in this repo. Every case here was manually verified
# by hand at least once during development; this persists that
# verification as an enforced regression suite.

SCRIPT="$BATS_TEST_DIRNAME/../../actions/set-version/validate-version.sh"

setup() {
  TEST_REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO" || exit 1
  git init -q
  git config user.email t@t.com
  git config user.name t
  echo a > f && git add . && git commit -qm init
  git branch -m main
  git tag v1.0.0
  echo b > f && git add . && git commit -qm second
  git tag v1.2.0
  echo c > f && git add . && git commit -qm third
  # HEAD is now 2 commits past v1.2.0 (the closest tag), matching a
  # real repo mid-development — v1.0.0 exists but is NOT the closest.
  GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  export GITHUB_OUTPUT
}

run_validate() {
  LANGUAGE="$1" VERSION="$2" TAG_PREFIX="v" BRANCH="$3" run bash "$SCRIPT"
}

output_has() {
  grep -qF "$1" "$GITHUB_OUTPUT"
}

@test "java main: valid bump succeeds, no suffix" {
  run_validate java 1.3.0 main
  [ "$status" -eq 0 ]
  output_has "validated-version=1.3.0"
  output_has "success=true"
}

@test "java main: equal to closest tag fails" {
  run_validate java 1.2.0 main
  [ "$status" -eq 1 ]
  output_has "success=false"
  output_has "validated-version="
}

@test "java main: less than closest tag fails" {
  run_validate java 1.1.0 main
  [ "$status" -eq 1 ]
}

@test "java develop: equal to closest tag succeeds with -SNAPSHOT" {
  run_validate java 1.2.0 develop
  [ "$status" -eq 0 ]
  output_has "validated-version=1.2.0-SNAPSHOT"
}

@test "java develop: greater than closest tag succeeds with -SNAPSHOT" {
  run_validate java 1.3.0 develop
  [ "$status" -eq 0 ]
  output_has "validated-version=1.3.0-SNAPSHOT"
}

@test "java develop: less than closest tag fails" {
  run_validate java 1.1.0 develop
  [ "$status" -eq 1 ]
}

@test "node develop: equal to closest tag succeeds with -dev" {
  run_validate node 1.2.0 develop
  [ "$status" -eq 0 ]
  output_has "validated-version=1.2.0-dev"
}

@test "node develop: less than closest tag fails" {
  run_validate node 1.1.0 develop
  [ "$status" -eq 1 ]
}

@test "node main: equal to closest tag fails (node unaffected by dev suffix relaxation)" {
  run_validate node 1.2.0 main
  [ "$status" -eq 1 ]
}

@test "node main: valid bump succeeds, no suffix" {
  run_validate node 1.3.0 main
  [ "$status" -eq 0 ]
  output_has "validated-version=1.3.0"
}

@test "feature branch: comparison skipped entirely, even for a version below every tag" {
  run_validate java 0.0.1 "feat/whatever"
  [ "$status" -eq 0 ]
  output_has "validated-version=0.0.1"
}

@test "feature branch: java gets no dev suffix, only develop does" {
  run_validate java 5.0.0 "feat/whatever"
  [ "$status" -eq 0 ]
  output_has "validated-version=5.0.0"
}

@test "bootstrap: no tags yet still succeeds and still applies dev suffix on develop" {
  cd "$BATS_TEST_TMPDIR" || exit 1
  mkdir fresh && cd fresh || exit 1
  git init -q
  git config user.email t@t.com
  git config user.name t
  echo x > f && git add . && git commit -qm init
  git branch -m develop
  GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  LANGUAGE=java VERSION=0.1.0 TAG_PREFIX=v BRANCH=develop GITHUB_OUTPUT="$GITHUB_OUTPUT" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF "validated-version=0.1.0-SNAPSHOT" "$GITHUB_OUTPUT"
}

@test "leading v is stripped from human input" {
  run_validate java v1.3.0 main
  [ "$status" -eq 0 ]
  output_has "validated-version=1.3.0"
}

@test "leading V (capital) is also stripped" {
  run_validate java V1.3.0 main
  [ "$status" -eq 0 ]
  output_has "validated-version=1.3.0"
}

@test "invalid language is rejected" {
  run_validate python 1.3.0 main
  [ "$status" -eq 1 ]
  output_has "language must be 'node' or 'java'"
}

@test "malformed version (missing patch) is rejected" {
  run_validate java 1.3 main
  [ "$status" -eq 1 ]
  output_has "not a valid X.Y.Z semantic version"
}

@test "malformed version (non-numeric) is rejected" {
  run_validate java 1.x.0 main
  [ "$status" -eq 1 ]
}

setup_numeric_repo() {
  # Isolated from the shared setup()'s repo/tags — multiple tags on the
  # same commit make git describe's tie-break implementation-defined, so
  # each of these gets its own single-tag history instead.
  cd "$BATS_TEST_TMPDIR" || exit 1
  mkdir numeric && cd numeric || exit 1
  git init -q
  git config user.email t@t.com
  git config user.name t
  echo x > f && git add . && git commit -qm init
  git branch -m main
  git tag "$1"
  GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  export GITHUB_OUTPUT
}

@test "numeric comparison, not lexicographic: 1.4.10 beats 1.4.9" {
  setup_numeric_repo v1.4.9
  run_validate java 1.4.10 main
  [ "$status" -eq 0 ]
  output_has "validated-version=1.4.10"
}

@test "numeric comparison, not lexicographic: 1.4.2 does not beat 1.4.10" {
  setup_numeric_repo v1.4.10
  run_validate java 1.4.2 main
  [ "$status" -eq 1 ]
}
