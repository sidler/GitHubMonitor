#!/bin/bash
# Creates a self-signed code signing certificate so the app has a stable
# identity across rebuilds.
#
# Why this matters: an ad-hoc signature (`codesign -s -`) is no identity at
# all. Little Snitch reports "the process has no code signature" and asks
# again after every build, and the Keychain treats each build as a different
# application, so the stored token needs re-authorising every time.
#
# Run once:  ./Scripts/create-signing-certificate.sh
# Then just build as usual; the Makefile picks the certificate up on its own.

set -euo pipefail

NAME="GitHub Monitor Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "A certificate named '$NAME' already exists — nothing to do."
    security find-identity -v -p codesigning | grep "$NAME" || true
    exit 0
fi

echo "Creating a self-signed code signing certificate '$NAME'…"

# codesign only accepts a certificate carrying the codeSigning extended key
# usage, so the extensions have to be spelled out.
cat > "$WORK_DIR/openssl.cnf" <<'CONF'
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no

[ dn ]
CN = GitHub Monitor Dev

[ v3 ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" \
    -config "$WORK_DIR/openssl.cnf" 2>/dev/null

# OpenSSL 3 defaults to AES-256 and a SHA-256 MAC, which Apple's security
# tool cannot read -- it fails with "MAC verification failed". The legacy PBE
# algorithms below are what it expects. An empty export password is also
# unreliable here, so a throwaway one is used and passed straight back in.
EXPORT_PASSWORD="ghm-$$-$RANDOM"
openssl pkcs12 -export -out "$WORK_DIR/identity.p12" \
    -inkey "$WORK_DIR/key.pem" -in "$WORK_DIR/cert.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout "pass:$EXPORT_PASSWORD" 2>/dev/null

echo
echo "macOS will now ask for your login password to add the certificate to"
echo "your keychain, and again to trust it for code signing."
echo

# -T grants codesign access to the private key without prompting on each build.
security import "$WORK_DIR/identity.p12" -k "$KEYCHAIN" -P "$EXPORT_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security

# Without a trust setting the identity is present but not considered valid,
# and `codesign -s` refuses to use it.
security add-trusted-cert -d -r trustRoot -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain-db" "$WORK_DIR/cert.pem" 2>/dev/null \
    || security add-trusted-cert -r trustRoot -p codeSign \
        -k "$HOME/Library/Keychains/login.keychain-db" "$WORK_DIR/cert.pem"

echo
if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "Done. Signing identity is available:"
    security find-identity -v -p codesigning | grep "$NAME"
    echo
    echo "Run 'make run' — the app is now signed with a stable identity."
    echo "Little Snitch and the Keychain will ask once more, then remember it."
else
    echo "The certificate was imported but is not yet listed as a valid"
    echo "signing identity. Open Keychain Access, find '$NAME', and set"
    echo "'Code Signing' to 'Always Trust' in its Trust section."
    exit 1
fi
