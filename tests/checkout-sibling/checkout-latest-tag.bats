#!/usr/bin/env bats
# Covers actions/checkout-sibling/checkout-latest-tag.sh's tag
# resolution — load-bearing for release-node-application.yml's pin
# step, which needs the sibling's latest tag specifically, not its
# default branch HEAD (see checkout-sibling/action.yml's description
# for why: a release commit here is never pushed to main itself, only
# to the tag it points to).

SCRIPT="$BATS_TEST_DIRNAME/../../actions/checkout-sibling/checkout-latest-tag.sh"

setup() {
  TEST_REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO" || exit 1
  git init -q
  git config user.email t@t.com
  git config user.name t
}

current_commit_message() {
  git log -1 --format=%s
}

@test "checks out the latest tag, not the branch tip past it" {
  echo a > f && git add . && git commit -qm "first"
  git tag v1.0.0
  echo b > f && git add . && git commit -qm "second, past the tag"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(current_commit_message)" = "first" ]
}

@test "resolves the most recently tagged commit when multiple tags exist" {
  echo a > f && git add . && git commit -qm "v1"
  git tag v1.0.0
  echo b > f && git add . && git commit -qm "v2"
  git tag v2.0.0
  echo c > f && git add . && git commit -qm "untagged work in progress"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(current_commit_message)" = "v2" ]
}

@test "fails clearly when there are no tags at all" {
  echo a > f && git add . && git commit -qm "no tags yet"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}
