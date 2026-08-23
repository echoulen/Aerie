#!/usr/bin/env bash
#
# Installs (or updates) Aerie.app from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/echoulen/Aerie/main/install.sh | bash
#
# Downloads the self-signed release zip for the current Mac's architecture,
# quits any running Aerie, replaces /Applications/Aerie.app, strips the
# quarantine flag (so there's no "right-click → Open" Gatekeeper dance), and
# relaunches it. Mirrors what `make install` does for a source checkout, minus
# the build step.

set -euo pipefail

REPO="echoulen/Aerie"
APP_NAME="Aerie"
APP_BUNDLE="${APP_NAME}.app"
INSTALL_DIR="/Applications"

log() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Aerie is macOS-only."

ARCH="$(uname -m)"
case "$ARCH" in
  arm64|x86_64) ;;
  *) die "Unsupported architecture: $ARCH" ;;
esac

ASSET_NAME="${APP_NAME}-macOS-${ARCH}.zip"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

log "Downloading latest ${APP_NAME} (${ARCH})…"
ZIP_PATH="${WORK_DIR}/${ASSET_NAME}"
if ! curl -fsSL "$DOWNLOAD_URL" -o "$ZIP_PATH"; then
  die "Couldn't download $DOWNLOAD_URL — is there a published release for $ARCH?"
fi

log "Unpacking…"
ditto -x -k "$ZIP_PATH" "$WORK_DIR" \
  || die "Couldn't unpack the downloaded zip."
[ -d "${WORK_DIR}/${APP_BUNDLE}" ] || die "Downloaded zip didn't contain ${APP_BUNDLE}."

# Stop any running instance before we swap the bundle — same sequence as
# `make install`: Apple Events Quit first (lets AppKit save state cleanly),
# then a polled grace period, then SIGKILL as a backstop for a delegate that
# swallows SIGTERM, then wait for the process to actually be reaped so the
# copy below doesn't race a dying process still mapping the old binary.
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  log "Stopping running ${APP_NAME}…"
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 1
  done
  pkill -9 -x "$APP_NAME" 2>/dev/null || true
  while pgrep -x "$APP_NAME" >/dev/null 2>&1; do sleep 0.2; done
fi

log "Installing to ${INSTALL_DIR}/${APP_BUNDLE}…"
rm -rf "${INSTALL_DIR:?}/${APP_BUNDLE}"
cp -R "${WORK_DIR}/${APP_BUNDLE}" "${INSTALL_DIR}/${APP_BUNDLE}"

# The zip was downloaded over the network, so macOS tagged it (and everything
# ditto unpacked from it) com.apple.quarantine. Running this script via
# curl | bash is already the user's trust decision, so strip it here instead
# of making them right-click → Open on first launch.
xattr -dr com.apple.quarantine "${INSTALL_DIR}/${APP_BUNDLE}" 2>/dev/null || true

open "${INSTALL_DIR}/${APP_BUNDLE}"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "${INSTALL_DIR}/${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || echo "unknown")"
log "✅ Installed ${APP_NAME} ${VERSION}."
