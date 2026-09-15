# Mesh Notes - Build Tools

## Overview

This document describes Mesh Notes build and distribution tools: the end-to-end macOS release packaging flow and an opt-in Gradle diagnostic script for Android builds.

**Location**: [tools/](../tools/)

## macOS DMG packaging and Apple notarization

[`tools/package_macos_dmg.sh`](../tools/package_macos_dmg.sh) builds the Flutter macOS release, signs its nested code and app bundle with hardened runtime, creates and signs a compressed DMG, optionally submits it to Apple's notarization service, and staples the accepted ticket. Keeping these steps in one entry point prevents an unsigned app from accidentally being packaged or submitted.

The script uses [`macos/Runner/Release.entitlements`](../macos/Runner/Release.entitlements) when signing the top-level app so the release retains MeshNotes' sandbox, network, microphone, and JIT capabilities. Nested dylibs, frameworks, and app extensions are signed inside-out before the app bundle; `codesign --deep` is intentionally not used.

### One-time setup

Run on macOS with Xcode command-line tools, FVM, and a **Developer ID Application** certificate (including its private key) installed in the current user's keychain. If the script is invoked from an automation environment whose `HOME` points at a sandbox, it switches to the real macOS user home before calling `security`, `codesign`, `notarytool`, and FVM so the login keychain and Flutter cache are visible.

Copy the committed template to the dedicated, gitignored secrets file:

```bash
cp .env.notarize.example .env.notarize
chmod 600 .env.notarize
```

Set `MACOS_CODESIGN_IDENTITY`, then configure exactly one `notarytool` authentication method:

- App Store Connect API key: `APPLE_API_KEY_PATH` (an absolute path to a `.p8` file outside this repository), `APPLE_API_KEY_ID`, and `APPLE_API_ISSUER`.
- Apple ID: `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`.
- macOS Keychain profile: first run `xcrun notarytool store-credentials meshnotes-notary ...`, then set `MACOS_NOTARY_KEYCHAIN_PROFILE=meshnotes-notary`.

The local `.env.notarize` is ignored by [`.gitignore`](../.gitignore). Never place real certificates, API keys, app-specific passwords, or `.p8` files in `.env.notarize.example`, Flutter `--dart-define` files, or source control.

### Usage

From the repository root:

```bash
./tools/package_macos_dmg.sh --dry-run
./tools/package_macos_dmg.sh
./tools/package_macos_dmg.sh --skip-build
./tools/package_macos_dmg.sh --skip-notarize
```

The normal flow runs `fvm flutter build macos --release`, signs `build/macos/Build/Products/Release/MeshNotes.app`, and writes `dist/MeshNotes-<version>-macos-<arch>.dmg`. The generated `dist/` directory is gitignored.

`--skip-build` reuses the existing release app. Before signing, the script verifies that its bundle ID matches `xyz.meshnotes.meshnotes` (or the intentional `MACOS_BUNDLE_ID` override). `--skip-notarize` produces a signed DMG without contacting Apple. `--dry-run` validates tools, env syntax, required variables, signing identity/private-key usability, release entitlements, and notarization credential selection without changing the app, creating a DMG, or contacting Apple. If the default env file has not been created yet, dry-run prints setup guidance and exits successfully.

The env parser accepts blank lines, comments, and quoted or unquoted `KEY=VALUE` entries. Secrets are not accepted as command-line flags, which avoids putting them in shell history. Environment values are loaded from the explicitly selected `--env-file`; use that option only for another protected local file.

Notarization uses the supported `xcrun notarytool submit --wait` flow. Apple progress and the submission ID remain visible. A failed submission exits before stapling; use the printed ID with `xcrun notarytool log` and the same authentication method. A successful submission is stapled and validated with `xcrun stapler`.

Useful verification commands:

```bash
codesign --verify --deep --strict --verbose=2 build/macos/Build/Products/Release/MeshNotes.app
codesign --verify --strict --verbose=2 dist/MeshNotes-<version>-macos-<arch>.dmg
xcrun stapler validate dist/MeshNotes-<version>-macos-<arch>.dmg
spctl --assess --type open --context context:primary-signature -vv dist/MeshNotes-<version>-macos-<arch>.dmg
```

If `codesign` reports `errSecInternalComponent` while the identity appears in `security find-identity -v -p codesigning`, unlock the login keychain and confirm the certificate has an accessible private key.

## Android Gradle configuration diagnostics

[`tools/gradle_diagnose_init.gradle`](../tools/gradle_diagnose_init.gradle) reports Gradle configuration-phase failures immediately instead of allowing them to be swallowed by Gradle's failure renderer.

Use it when `flutter build apk` or `appbundle` remains at `Running Gradle task 'assembleRelease'...` after configuration has already failed:

```bash
cd android
./gradlew :<plugin_project>:properties -I ../tools/gradle_diagnose_init.gradle
./gradlew :app:assembleRelease -I ../tools/gradle_diagnose_init.gradle
```

On Windows use `gradlew.bat`. Search output for `#### DIAG FAILURE`; the numbered cause chain includes suppressed exceptions and a circular-cause guard. Because the init script runs only when explicitly supplied with `-I`, it does not affect normal builds.
