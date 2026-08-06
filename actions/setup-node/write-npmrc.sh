#!/usr/bin/env bash
# Reads NPMRC from the environment and writes it verbatim to ~/.npmrc.
printf '%s' "$NPMRC" > ~/.npmrc
