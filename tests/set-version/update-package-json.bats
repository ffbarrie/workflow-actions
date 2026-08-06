#!/usr/bin/env bats
# Covers actions/set-version/update-package-json.sh's packages/* lockstep
# sync — the root package.json update itself is a thin npm version
# wrapper, not worth testing in isolation, but the sync loop (private
# filtering, no-packages/-dir no-op) is real logic.

SCRIPT="$BATS_TEST_DIRNAME/../../actions/set-version/update-package-json.sh"

setup() {
  TEST_REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO" || exit 1
}

write_pkg() {
  # write_pkg <path> <version> [private]
  mkdir -p "$(dirname "$1")"
  if [ "${3:-}" = "private" ]; then
    printf '{"name":"pkg","version":"%s","private":true}\n' "$2" > "$1"
  else
    printf '{"name":"pkg","version":"%s"}\n' "$2" > "$1"
  fi
}

run_update() {
  VALIDATED_VERSION="$1" run bash "$SCRIPT"
}

pkg_version() {
  node -p "require('./$1').version"
}

@test "root only, no packages/ dir: updates root, no error" {
  write_pkg package.json 1.0.0
  run_update 1.2.0
  [ "$status" -eq 0 ]
  [ "$(pkg_version package.json)" = "1.2.0" ]
}

@test "packages/*: non-private package forced to root version" {
  write_pkg package.json 1.0.0
  write_pkg packages/foo/package.json 0.9.0
  run_update 1.2.0
  [ "$status" -eq 0 ]
  [ "$(pkg_version packages/foo/package.json)" = "1.2.0" ]
}

@test "packages/*: private package is left untouched" {
  write_pkg package.json 1.0.0
  write_pkg packages/internal/package.json 0.9.0 private
  run_update 1.2.0
  [ "$status" -eq 0 ]
  [ "$(pkg_version packages/internal/package.json)" = "0.9.0" ]
}

@test "packages/*: multiple publishable packages all synced together" {
  write_pkg package.json 1.0.0
  write_pkg packages/foo/package.json 0.9.0
  write_pkg packages/bar/package.json 0.5.0
  write_pkg packages/internal/package.json 0.1.0 private
  run_update 2.0.0
  [ "$status" -eq 0 ]
  [ "$(pkg_version package.json)" = "2.0.0" ]
  [ "$(pkg_version packages/foo/package.json)" = "2.0.0" ]
  [ "$(pkg_version packages/bar/package.json)" = "2.0.0" ]
  [ "$(pkg_version packages/internal/package.json)" = "0.1.0" ]
}

@test "packages/ dir exists but is empty: still succeeds" {
  write_pkg package.json 1.0.0
  mkdir -p packages
  run_update 1.2.0
  [ "$status" -eq 0 ]
  [ "$(pkg_version package.json)" = "1.2.0" ]
}
