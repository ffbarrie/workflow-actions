#!/usr/bin/env bash
# Runs in the sibling's checkout directory (working-directory, set by the
# calling step). Requires the checkout to have fetch-depth: 0 and
# fetch-tags: true — otherwise git describe silently finds no tags.
set -euo pipefail

tag=$(git describe --tags --abbrev=0)
echo "Resolved latest tag: $tag"
git checkout --quiet "$tag"
