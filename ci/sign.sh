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
"$bt/apksigner" sign --v2-signing-enabled true --v3-signing-enabled true --ks "$KS_FILE" --ks-key-alias "$KEY_ALIAS" \
  --ks-pass env:KS_PASS --key-pass env:KEY_PASS --out "$out" "$work/aligned.apk"
rm -f "$out.idsig"

schemes=$("$bt/apksigner" verify --verbose "$out" | grep -E '^Verified using v[0-9]' || true)
echo "$schemes"
for v in v2 v3; do
  grep -q "^Verified using $v scheme.*: true" <<<"$schemes" || { echo "APK is not signed with $v" >&2; exit 1; }
done
certs=$("$bt/apksigner" verify --print-certs "$out")
# Line labels differ between build-tools versions ("Signer #1 certificate SHA-256 digest: ..." or
# "Signer (minSdkVersion=...) certificate SHA-256 digest: ..."); collect the distinct digests.
digests=$(sed -nE 's/.*certificate SHA-256 digest: *([0-9a-fA-F:]+).*/\1/p' <<<"$certs" | tr -d ':' | tr A-F a-f | sort -u)
n=$(grep -c . <<<"$digests" || true)
[ "$n" = 1 ] || { echo "expected exactly one signer certificate, got $n:" >&2; echo "$certs" >&2; exit 1; }
got=$digests
echo "signer SHA-256: $got"

if [ "${SIGN_SELFTEST:-0}" != 1 ]; then
  want=$(tr -d ': \n' <<<"${EXPECT_SHA256:-}" | tr A-F a-f)
  [ -n "$want" ] || { echo "RELEASE_CERT_SHA256 variable is not set" >&2; exit 1; }
  [ "$got" = "$want" ] || { echo "signer does not match RELEASE_CERT_SHA256 (wrong keystore?)" >&2; exit 1; }
fi
