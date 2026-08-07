#!/usr/bin/env bats
# Covers actions/docker-build-scan-push/push-image.sh's TAG_LIST
# splitting — stubs `docker` so no real image or daemon is needed, just
# records what push-image.sh actually invoked it with.

SCRIPT="$BATS_TEST_DIRNAME/../../actions/docker-build-scan-push/push-image.sh"

setup() {
  STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR"
  PUSH_LOG="$BATS_TEST_TMPDIR/pushes.log"
  : > "$PUSH_LOG"
  cat > "$STUB_DIR/docker" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$PUSH_LOG"
EOF
  chmod +x "$STUB_DIR/docker"
  PATH="$STUB_DIR:$PATH"
  export PATH PUSH_LOG
}

@test "single tag: docker push called once" {
  TAG_LIST=ghcr.io/my-app:latest run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$PUSH_LOG" | tr -d ' ')" -eq 1 ]
  grep -qF "push ghcr.io/my-app:latest" "$PUSH_LOG"
}

@test "multiple tags: docker push called once per tag, in order" {
  TAG_LIST="ghcr.io/my-app:v1.2.3,ghcr.io/my-app:latest" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$PUSH_LOG" | tr -d ' ')" -eq 2 ]
  [ "$(sed -n 1p "$PUSH_LOG")" = "push ghcr.io/my-app:v1.2.3" ]
  [ "$(sed -n 2p "$PUSH_LOG")" = "push ghcr.io/my-app:latest" ]
}

@test "a failing push aborts the remaining pushes (set -e)" {
  cat > "$STUB_DIR/docker" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$PUSH_LOG"
if [[ "\$2" == *fail* ]]; then exit 1; fi
EOF
  chmod +x "$STUB_DIR/docker"
  TAG_LIST="ghcr.io/my-app:fail,ghcr.io/my-app:never-reached" run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ "$(wc -l < "$PUSH_LOG" | tr -d ' ')" -eq 1 ]
}
