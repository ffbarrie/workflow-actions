#!/usr/bin/env bats
# Covers actions/get-version/read-version.sh's per-language dev-suffix
# stripping — load-bearing for the release-*.yml workflows, since
# base-version feeds straight into set-version to compute the release
# version.

SCRIPT="$BATS_TEST_DIRNAME/../../actions/get-version/read-version.sh"

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1
  GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  export GITHUB_OUTPUT
}

output_has() {
  grep -qF "$1" "$GITHUB_OUTPUT"
}

@test "node: -dev suffix is stripped into base-version, is-snapshot true" {
  echo '{"name":"t","version":"1.1.0-dev"}' > package.json
  LANGUAGE=node run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  output_has "version=1.1.0-dev"
  output_has "base-version=1.1.0"
  output_has "is-snapshot=true"
}

@test "node: plain version has no suffix to strip, is-snapshot false" {
  echo '{"name":"t","version":"1.1.0"}' > package.json
  LANGUAGE=node run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  output_has "version=1.1.0"
  output_has "base-version=1.1.0"
  output_has "is-snapshot=false"
}

@test "java: -SNAPSHOT suffix is stripped into base-version, is-snapshot true" {
  cat > pom.xml <<'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>t</artifactId>
  <version>1.1.0-SNAPSHOT</version>
</project>
EOF
  LANGUAGE=java run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  output_has "version=1.1.0-SNAPSHOT"
  output_has "base-version=1.1.0"
  output_has "is-snapshot=true"
}

@test "java: plain version has no suffix to strip, is-snapshot false" {
  cat > pom.xml <<'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>t</artifactId>
  <version>1.1.0</version>
</project>
EOF
  LANGUAGE=java run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  output_has "base-version=1.1.0"
  output_has "is-snapshot=false"
}

@test "node's -dev is not stripped when read as java (cross-language suffix mismatch)" {
  # Sanity check that the suffix choice is genuinely per-language, not a
  # blanket strip of both — a java pom.xml literally ending in -dev
  # (unusual, but not this script's business to reject) should NOT be
  # treated as a dev version, since java's suffix is -SNAPSHOT.
  cat > pom.xml <<'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>t</artifactId>
  <version>1.1.0-dev</version>
</project>
EOF
  LANGUAGE=java run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  output_has "base-version=1.1.0-dev"
  output_has "is-snapshot=false"
}

@test "invalid language is rejected" {
  LANGUAGE=python run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}
