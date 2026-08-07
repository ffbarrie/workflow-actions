#!/usr/bin/env bats
# Covers actions/setup-node/install-dependencies.sh's package-manager
# case statement and the install-command override — stubs npm/pnpm/yarn
# so no real install runs, just records what got invoked.

SCRIPT="$BATS_TEST_DIRNAME/../../actions/setup-node/install-dependencies.sh"

setup() {
  STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR"
  CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
  : > "$CALL_LOG"
  for cmd in npm pnpm yarn; do
    cat > "$STUB_DIR/$cmd" <<EOF
#!/usr/bin/env bash
echo "$cmd \$@" >> "$CALL_LOG"
EOF
    chmod +x "$STUB_DIR/$cmd"
  done
  PATH="$STUB_DIR:$PATH"
  export PATH CALL_LOG
}

@test "npm: runs npm ci" {
  PACKAGE_MANAGER=npm INSTALL_COMMAND="" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$CALL_LOG")" = "npm ci" ]
}

@test "pnpm: runs pnpm install --frozen-lockfile" {
  PACKAGE_MANAGER=pnpm INSTALL_COMMAND="" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$CALL_LOG")" = "pnpm install --frozen-lockfile" ]
}

@test "yarn: runs yarn install --immutable" {
  PACKAGE_MANAGER=yarn INSTALL_COMMAND="" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$CALL_LOG")" = "yarn install --immutable" ]
}

@test "unknown package manager fails clearly instead of silently doing nothing" {
  PACKAGE_MANAGER=bun INSTALL_COMMAND="" run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -s "$CALL_LOG" ]
}

@test "install-command override bypasses the package-manager case entirely" {
  PACKAGE_MANAGER=npm INSTALL_COMMAND="npm install --legacy-peer-deps" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$CALL_LOG")" = "npm install --legacy-peer-deps" ]
}

@test "install-command override works even for an otherwise-unknown package manager" {
  PACKAGE_MANAGER=bun INSTALL_COMMAND="npm ci" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$CALL_LOG")" = "npm ci" ]
}
