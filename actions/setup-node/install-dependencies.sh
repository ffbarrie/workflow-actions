#!/usr/bin/env bash
# Reads INSTALL_COMMAND and PACKAGE_MANAGER from the environment. Runs in
# working-directory (set by the calling step).
if [ -n "$INSTALL_COMMAND" ]; then
  eval "$INSTALL_COMMAND"
else
  case "$PACKAGE_MANAGER" in
    npm)  npm ci ;;
    pnpm) pnpm install --frozen-lockfile ;;
    yarn) yarn install --immutable ;;
    *) echo "::error::Unknown package-manager: $PACKAGE_MANAGER" >&2; exit 1 ;;
  esac
fi
