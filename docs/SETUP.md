# One-time setup

Everything here is done by you, in the GitHub web UI and on your own PC. The release keystore and
its password never go into a chat, a repo, or anywhere but GitHub's encrypted secrets and your
offline backup.

## 1. Make the release keystore (your PC, offline)

One key signs every app, for good: Android only accepts an update signed with the same key, so if
it is lost, every app has to be uninstalled and reinstalled. Needs a JDK (`keytool`).

```sh
keytool -genkeypair -v -keystore release.jks -alias release \
  -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=<your name>"
```

It asks for a password once (a PKCS12 keystore uses the same password for the store and the key).
Then:

```sh
keytool -list -v -keystore release.jks -alias release | grep 'SHA256:'
```

Note that SHA-256 fingerprint (it is public, not a secret). Base64 the file for GitHub:

- Linux/macOS: `base64 -w0 release.jks > release.jks.b64` (macOS: `base64 -i release.jks -o release.jks.b64`)
- Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks")) | Set-Content release.jks.b64`

Back up `release.jks` and the password offline (two places, e.g. a USB stick in a drawer and a
password manager). Delete `release.jks.b64` once it is in GitHub.

## 2. Protect main

*Settings → Rules → Rulesets → New branch ruleset*: target the default branch, enable
**Restrict deletions**, **Block force pushes**, and **Require a pull request before merging**.
Signing only ever runs from main, so this is what stands between a stray push and your key.

*Settings → Actions → General*: Workflow permissions **Read repository contents** (the workflow
asks for write only where it creates releases).

## 3. Environment and secrets

*Settings → Environments → New environment* `release-signing`:

- **Deployment branches and tags**: *Selected branches* → add `main`.
- Optional: **Required reviewers** → yourself, if you want to approve every signing run as well
  (the pre-release → promote step is already your gate for what reaches devices).
- **Environment secrets**:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_B64` | contents of `release.jks.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `release` |
| `ANDROID_KEY_PASSWORD` | the same password (PKCS12) |
| `NOTIFY_URL` | optional: a webhook (e.g. n8n) that gets `{app, status, tag, run}` after each publish |

- **Environment variables**: `RELEASE_CERT_SHA256` = the SHA-256 fingerprint from step 1. The
  publish job refuses to release an APK whose signer doesn't match it.

Repository secret (*Settings → Secrets and variables → Actions*), only if app repos are private:

| Secret | Value |
|---|---|
| `SOURCE_READ_TOKEN` | fine-grained token: *Only select repositories* (the app repos), *Contents: Read-only*, nothing else |

The build job runs the app's own build scripts, so it gets only this read token, never the key.

## 4. First build

*Actions → android → Run workflow* on `main`, app `all` (or one app). Each app gets a
pre-release `<app> <version>` under *Releases*. To deploy one: open it → *Edit* → untick
**Set as a pre-release** → *Update release*.

## 5. Obtainium, per app, per device

Add app → source URL `https://github.com/cstone1983/app-builder`, then in its settings:

| Setting | Value |
|---|---|
| Include prereleases | **off** (only promoted releases install) |
| Fall back to older releases | **on** (needed: the newest release is often another app's) |
| Filter release titles by regular expression | `^voice-keyboard ` (the app id and a space) |
| Filter APKs by regular expression | `^voice-keyboard-.*\.apk$` |

App ids: `voice-keyboard`, `sshsync`, `hvac`, `nightfall` (see apps.json).

Obtainium's check interval can go down to 15-30 minutes. Silent background installs work on
Android 12+ when Obtainium did the first install; otherwise it asks, or use Shizuku. A GitHub token
in Obtainium is optional (the repo is public; it only raises the API rate limit).

**Switching keys, once per app:** apps installed today are signed with other keys, so Android
won't take the new release as an update. Uninstall the old one (export its data first if it has
any on the device) and install through Obtainium. After that, every update is in place.

## Housekeeping

- The workflow keeps the 10 newest pre-releases per app and deletes older ones. Promoted releases
  are kept; delete old ones now and then (Obtainium only looks at the newest 100 releases).
- To build automatically on every push to an app, add a workflow to the app repo that sends a
  `repository_dispatch` (needs a fine-grained token for app-builder with *Contents: Read and
  write*, saved in the app repo as `DISPATCH_TOKEN`):

```yaml
on: { push: { branches: [main] } }
jobs:
  dispatch:
    runs-on: ubuntu-latest
    steps:
      - run: |
          curl -fsS -X POST -H "Authorization: Bearer $T" -H "Accept: application/vnd.github+json" \
            https://api.github.com/repos/cstone1983/app-builder/dispatches \
            -d '{"event_type":"build","client_payload":{"app":"<app id>"}}'
        env: { T: "${{ secrets.DISPATCH_TOKEN }}" }
```
