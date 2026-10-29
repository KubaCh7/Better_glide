#!/bin/bash
# Signs BetterGlide.app with the self-signed identity from the SIGNING_CERT_P12 (base64)
# and SIGNING_CERT_PASSWORD environment variables, using a throwaway keychain.
# Usage: scripts/sign-app.sh path/to/BetterGlide.app
set -euo pipefail

APP="$1"
: "${SIGNING_CERT_P12:?missing}" "${SIGNING_CERT_PASSWORD:?missing}"
WORK="$(mktemp -d)"
KEYCHAIN="$WORK/signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
ORIGINAL_KEYCHAINS="$(security list-keychains -d user | tr -d '"')"

cleanup() {
  # shellcheck disable=SC2086
  security list-keychains -d user -s $ORIGINAL_KEYCHAINS || true
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

printf '%s' "$SIGNING_CERT_P12" | base64 --decode > "$WORK/cert.p12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$SIGNING_CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $ORIGINAL_KEYCHAINS

IDENTITY="$(security find-certificate -c "BetterGlide Self-Signed" -Z "$KEYCHAIN" | awk '/SHA-1 hash/ {print $NF}')"
[ -n "$IDENTITY" ] || { echo "Signing certificate not found in the p12"; exit 1; }

codesign --force --deep --timestamp=none --keychain "$KEYCHAIN" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Designated requirement:"
codesign -d -r- "$APP" 2>&1 | grep designated
