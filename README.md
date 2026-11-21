# app-builder

Builds, signs and publishes my Android app releases. Phones and tablets get them through
[Obtainium](https://github.com/ImranR98/Obtainium), which watches this repo's releases.

```
app repo ──► build (unsigned, no secrets) ──► publish (env "release-signing", main only)
                                                 sign with the one release key
                                                 check the signer
                                                 create a PRE-release here
                                    you promote it to a full release ──► Obtainium installs it
```

- **apps.json**: the apps, where their source is, and how to build each one.
- **.github/workflows/android.yml**: the pipeline. Run it from *Actions → android → Run workflow*
  (pick an app or `all`), or with a `repository_dispatch` of type `build`.
- **ci/**: helper scripts: build matrix, the Gradle init script that makes the build unsigned and
  sets the version, and the signing script.
- **docs/SETUP.md**: one-time setup (keystore, secrets, environment, Obtainium).

Releases are named `<app> <version>` with tags `<app>-v<version>`; versions are the app's own
version plus the builder run number (e.g. `voice-keyboard 6.4.0.57`), and the versionCode is the
app's base from apps.json plus the run number, so every build installs over the previous one.

Nothing here changes the app repos.
