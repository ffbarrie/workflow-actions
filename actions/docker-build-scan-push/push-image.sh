#!/usr/bin/env bash
# Reads TAG_LIST (comma-separated, from the Build tag list step's output)
# from the environment and pushes each tag. The image was already built
# and loaded locally under all these tags, and already scanned — this
# step only runs if that scan passed.
set -euo pipefail
IFS=',' read -ra TAG_ARR <<< "$TAG_LIST"
for t in "${TAG_ARR[@]}"; do
  docker push "$t"
done
