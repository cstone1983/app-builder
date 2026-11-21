#!/usr/bin/env bash
# sign.sh <in.apk> <out.apk>
# Aligns and signs an APK with the release key, verifies it, and checks the signer.
# Env: KS_FILE (keystore path), KS_PASS, KEY_ALIAS, KEY_PASS, EXPECT_SHA256 (signer cert SHA-256,
# hex, colons/case ignored; required unless SIGN_SELFTEST=1). Passwords are passed to apksigner via
# env:, never on the command line. Any old signature on the input (e.g. Flutter's debug key) is
# replaced: apksigner drops existing signers' files and the old APK Signing Block.
set -euo pipefail
in=$1 out=$2
: "${KS_FILE:?}" "${KS_PASS:?}" "${KEY_ALIAS:?}" "${KEY_PASS:?}"

bt=$(ls -d "${ANDROID_HOME:?}"/build-tools/* | sort -V | tail -1)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 16 KB alignment for uncompressed native libraries (needed on 16 KB page-size devices).
"$bt/zipalign" -P 16 -f 4 "$in" "$work/aligned.apk"
"$bt/apksigner" sign --ks "$KS_FILE" --ks-key-alias "$KEY_ALIAS" \
  --ks-pass env:KS_PASS --key-pass env:KEY_PASS --out "$out" "$work/aligned.apk"
rm -f "$out.idsig"

"$bt/apksigner" verify --verbose "$out" | grep -E '^Verified using v[0-9]' || true
certs=$("$bt/apksigner" verify --print-certs "$out")
signers=$(grep -c 'certificate SHA-256 digest' <<<"$certs" || true)
got=$(grep -m1 'Signer #1 certificate SHA-256 digest' <<<"$certs" | awk -F': ' '{print $2}' | tr -d ': ' | tr A-F a-f)
[ "$signers" = 1 ] || { echo "expected exactly one signer, got $signers" >&2; exit 1; }
echo "signer SHA-256: $got"

if [ "${SIGN_SELFTEST:-0}" != 1 ]; then
  want=$(tr -d ': \n' <<<"${EXPECT_SHA256:-}" | tr A-F a-f)
  [ -n "$want" ] || { echo "RELEASE_CERT_SHA256 variable is not set" >&2; exit 1; }
  [ "$got" = "$want" ] || { echo "signer does not match RELEASE_CERT_SHA256 (wrong keystore?)" >&2; exit 1; }
fi
