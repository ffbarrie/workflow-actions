#!/usr/bin/env bash
# Reads VALIDATED_VERSION from the environment. Runs in working-directory
# (set by the calling step).
npm version "$VALIDATED_VERSION" --no-git-tag-version --allow-same-version
