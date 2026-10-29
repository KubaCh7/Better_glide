#!/bin/bash
# One-time setup (run on your Mac): creates a self-signed code-signing certificate for
# BetterGlide and stores it as GitHub Actions secrets.
#
# Why: macOS ties the Accessibility and Screen Recording permissions to the app's signature.
# Ad-hoc builds get a new signature every time, so every update would reset them. Builds
# signed with this certificate keep the same identity, so permissions survive updates.
# (A paid Apple Developer ID would do the same and also remove the Gatekeeper warning.)
#
# Usage: scripts/create-signing-certificate.sh [output-dir]
#        scripts/create-signing-certificate.sh --local-only <output-dir>   (CI self-test)
set -euo pipefail

LOCAL_ONLY=0
if [ "${1:-}" = "--local-only" ]; then LOCAL_ONLY=1; shift; fi
OUT="${1:-$HOME/BetterGlide-signing}"
NAME="BetterGlide Self-Signed"
REPO="KubaCh7/Better_glide"
# LibreSSL that ships with macOS writes PKCS#12 files that `security import` accepts.
OPENSSL=/usr/bin/openssl

mkdir -p "$OUT"
chmod 700 "$OUT"
cd "$OUT"
PASSWORD="$($OPENSSL rand -hex 16)"

cat > cert.cnf <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

$OPENSSL req -x509 -newkey rsa:2048 -nodes -days 3650 -config cert.cnf -keyout key.pem -out cert.pem 2>/dev/null
$OPENSSL pkcs12 -export -inkey key.pem -in cert.pem -name "$NAME" -out cert.p12 -passout "pass:$PASSWORD"
base64 < cert.p12 | tr -d '\n' > cert.p12.base64
printf '%s' "$PASSWORD" > password.txt
rm -f key.pem cert.cnf
echo "Certificate created in $OUT"

[ "$LOCAL_ONLY" = 1 ] && exit 0

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  gh secret set SIGNING_CERT_P12 --repo "$REPO" < cert.p12.base64
  gh secret set SIGNING_CERT_PASSWORD --repo "$REPO" --body "$PASSWORD"
  echo "Secrets SIGNING_CERT_P12 and SIGNING_CERT_PASSWORD saved in $REPO. Done!"
  exit 0
fi

# No GitHub CLI: add the two secrets by hand in the browser.
URL="https://github.com/$REPO/settings/secrets/actions/new"
pbcopy < cert.p12.base64
cat <<MSG

Add two secrets on GitHub (the page opens now): $URL

  1. Name: SIGNING_CERT_P12
     Value: already copied to the clipboard — just paste (Cmd+V) and click "Add secret".

  2. Click "New repository secret" again.
     Name: SIGNING_CERT_PASSWORD
     Value: $PASSWORD

Keep $OUT private (it contains the signing key); you only need it to set the secrets again.
MSG
open "$URL"
