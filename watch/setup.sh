#!/bin/sh
# One command from repo checkout to Xcode ready-to-run.
set -eu
cd "$(dirname "$0")"
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing xcodegen via Homebrew…"
    brew install xcodegen
  else
    echo "FIX xcodegen is required: install Homebrew, or 'mint install yonaskolb/XcodeGen'" >&2
    exit 1
  fi
fi
./tools/gen-device-key.sh
xcodegen generate
echo
echo "PASS Project ready. Opening Xcode — one-time: pick your Team under"
echo "     Signing & Capabilities, choose your watch as destination, press Run."
open AgentTap.xcodeproj
