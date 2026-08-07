#!/usr/bin/env bats
# Covers actions/set-version/update-application-release-yaml.sh — the
# missing-file guard and the app.version/app.build fields it writes via
# yq.

SCRIPT="$BATS_TEST_DIRNAME/../../actions/set-version/update-application-release-yaml.sh"

setup() {
  TEST_DIR="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1
}

@test "missing YAML_PATH fails clearly instead of yq erroring on it" {
  YAML_PATH=src/main/resources/application-release.yaml VALIDATED_VERSION=1.2.0 \
    run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "writes app.version and a UTC app.build timestamp, preserving other keys" {
  mkdir -p src/main/resources
  cat > src/main/resources/application-release.yaml <<'EOF'
app:
  version: 0.0.0
  build: unset
other:
  unrelated: keep-me
EOF
  YAML_PATH=src/main/resources/application-release.yaml VALIDATED_VERSION=1.2.0 \
    run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  version=$(yq '.app.version' src/main/resources/application-release.yaml)
  [ "$version" = "1.2.0" ]
  build=$(yq '.app.build' src/main/resources/application-release.yaml)
  [[ "$build" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
  unrelated=$(yq '.other.unrelated' src/main/resources/application-release.yaml)
  [ "$unrelated" = "keep-me" ]
}

@test "custom YAML_PATH is respected, not hardcoded to the default location" {
  mkdir -p custom/path
  echo 'app: {version: 0.0.0, build: unset}' > custom/path/release.yaml
  YAML_PATH=custom/path/release.yaml VALIDATED_VERSION=2.0.0 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  version=$(yq '.app.version' custom/path/release.yaml)
  [ "$version" = "2.0.0" ]
}
