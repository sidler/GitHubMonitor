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

# Verify the bundle before blaming the keychain for it later.
if ! openssl pkcs12 -in "$WORK_DIR/identity.p12" -passin "pass:$EXPORT_PASSWORD" -noout 2>/dev/null; then
    echo "Error: the generated PKCS#12 file cannot be read back with its own" >&2
    echo "password. That is an OpenSSL problem, not a keychain one." >&2
    exit 1
fi

echo
echo "macOS will now ask for your login password — first to unlock the"
echo "keychain, then to trust the certificate for code signing."
echo

# Importing into a locked keychain fails with a confusing "MAC verification
# failed (wrong password?)", which reads as if the PKCS#12 password were
# wrong. Unlock explicitly so any failure after this point is the real one.
if ! security unlock-keychain "$KEYCHAIN"; then
    echo "Could not unlock the keychain — see the manual route in README.md." >&2
    exit 1
fi

# -T grants codesign access to the private key without prompting on each build.
if ! security import "$WORK_DIR/identity.p12" -k "$KEYCHAIN" -P "$EXPORT_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security; then
    cat >&2 <<'HINT'

The import failed. The PKCS#12 file itself is valid — it was verified above —
so this is the keychain refusing it.

Create the certificate through the GUI instead, which is Apple's own route and
does not go through PKCS#12 at all:

  1. Open Keychain Access
  2. Menu: Keychain Access > Certificate Assistant > Create a Certificate…
  3. Name:              GitHub Monitor Dev
     Identity Type:     Self Signed Root
     Certificate Type:  Code Signing
  4. Tick "Let me override defaults", accept every following screen
  5. Run 'make bundle' — it picks the certificate up automatically

HINT
    exit 1
fi

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
