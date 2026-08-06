#!/usr/bin/env bash
# Reads REGISTRY, IMAGE_NAME, TAGS from the environment. Writes
# list/first to $GITHUB_OUTPUT: list is every fully-qualified tag
# (comma-separated), first is just the first one (for the scan step's
# image-ref — any tag references the same image content).
set -euo pipefail
image="${REGISTRY}/${IMAGE_NAME}"
IFS=',' read -ra TAG_ARR <<< "$TAGS"
out=""
for t in "${TAG_ARR[@]}"; do
  # trim leading/trailing whitespace so "v1, latest" (a natural way
  # to type it) doesn't produce an invalid tag with a stray space
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  out+="${image}:${t},"
done
echo "list=${out%,}" >> "$GITHUB_OUTPUT"
first="${TAG_ARR[0]}"
first="${first#"${first%%[![:space:]]*}"}"
first="${first%"${first##*[![:space:]]}"}"
echo "first=${image}:${first}" >> "$GITHUB_OUTPUT"
