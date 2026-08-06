#!/usr/bin/env bash
# Reads VALIDATED_VERSION from the environment. Runs in working-directory
# (set by the calling step).
mvn -B versions:set -DnewVersion="$VALIDATED_VERSION" -DgenerateBackupPoms=false
