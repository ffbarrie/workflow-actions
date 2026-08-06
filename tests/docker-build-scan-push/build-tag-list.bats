#!/usr/bin/env bats
# Covers actions/docker-build-scan-push/build-tag-list.sh's tag
# construction and whitespace trimming.

SCRIPT="$BATS_TEST_DIRNAME/../../actions/docker-build-scan-push/build-tag-list.sh"

setup() {
  GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  export GITHUB_OUTPUT
}

output_has() {
  grep -qF "$1" "$GITHUB_OUTPUT"
}

@test "single tag" {
  REGISTRY=ghcr.io IMAGE_NAME=my-app TAGS=latest run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  output_has "list=ghcr.io/my-app:latest"
  output_has "first=ghcr.io/my-app:latest"
}

@test "multiple tags, first is the first one listed" {
  REGISTRY=ghcr.io IMAGE_NAME=myorg/my-app TAGS="v1.2.3,latest" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  output_has "list=ghcr.io/myorg/my-app:v1.2.3,ghcr.io/myorg/my-app:latest"
  output_has "first=ghcr.io/myorg/my-app:v1.2.3"
}

@test "whitespace after commas is trimmed (a natural way to type multiple tags)" {
  REGISTRY=ghcr.io IMAGE_NAME=my-app TAGS="v1.2.3, latest, sha-abc123" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  output_has "list=ghcr.io/my-app:v1.2.3,ghcr.io/my-app:latest,ghcr.io/my-app:sha-abc123"
}

@test "leading whitespace on the first tag is trimmed too" {
  REGISTRY=ghcr.io IMAGE_NAME=my-app TAGS=" latest" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  output_has "first=ghcr.io/my-app:latest"
}
