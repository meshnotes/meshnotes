# Mesh Notes - Build Tools

## Overview

This document describes the build and distribution tools for Mesh Notes: macOS DMG creation, signing and notarization, plus a Gradle diagnostic script for Android builds.

**Location**: [tools/](../tools/)

## Tools

### gradle_diagnose_init.gradle - Android Configuration Failure Diagnostics

Reports Gradle configuration-phase failures immediately instead of letting them be swallowed.

**Location**: [tools/gradle_diagnose_init.gradle](../tools/gradle_diagnose_init.gradle)

**When to use it**: `flutter build apk`/`appbundle` prints `Running Gradle task 'assembleRelease'...` and never finishes, with no error message. Check whether the Gradle daemon is pinning one CPU core at a flat memory footprint — that means the build already failed and Gradle is stuck in `DefaultExceptionAnalyser.findDeepestRootException` building the failure report, so the real error will never be printed.

**Usage** (from `android/`):
```bash
# Reproduce with a cheap configuration-only task first
./gradlew :<plugin_project>:properties -I ../tools/gradle_diagnose_init.gradle

# Or during a real build
./gradlew :app:assembleRelease -I ../tools/gradle_diagnose_init.gradle
```

On Windows use `gradlew.bat`; if the wrapper cannot find a JDK, point `JAVA_HOME` at the one bundled with Android Studio:
```powershell
$env:JAVA_HOME="D:\Program Files\Android\Android Studio\jbr"
```

**Output**: search for `#### DIAG FAILURE`. The failure is printed as a numbered cause chain, including suppressed exceptions (often the actual cause, and the reason Gradle hangs in the first place) and a circular-cause guard so the script cannot loop the way Gradle does.

**Example** — this is how the `record_android` 1.5.2 build hang was traced to its root cause (see [04-platform-specific.md](04-platform-specific.md#6-android-build-hangs-at-running-gradle-task-assemblerelease)):
```
#### DIAG FAILURE: project :record_android
#### [0] org.gradle.api.ProjectConfigurationException: A problem occurred configuring project ':record_android'.
#### [1] org.gradle.api.GradleScriptException: A problem occurred evaluating project ':record_android'.
#### [2] groovy.lang.MissingPropertyException: Could not get unknown property 'flutter' for extension 'android' of type com.android.build.gradle.LibraryExtension.
#### END DIAG (depth=3)
```

The script only runs when passed explicitly with `-I`, so it never affects normal builds.

### build_dmg.sh - DMG Creation Tool

Creates a macOS DMG installer package from a built macOS application.

**Location**: [tools/build_dmg.sh](../tools/build_dmg.sh)

**Usage:**
```bash
./tools/build_dmg.sh [app_path] [output_dmg_path] [version]
```

**Parameters:**
- `app_path` - Path to MeshNotes.app (default: `build/macos/Build/Products/Release/MeshNotes.app`)
- `output_dmg_path` - Output DMG file path (default: `build/MeshNotes-{version}.dmg`)
- `version` - Version number (default: read from `pubspec.yaml`)

**Examples:**
```bash
# Use default parameters
./tools/build_dmg.sh

# Specify all parameters
./tools/build_dmg.sh \
    build/macos/Build/Products/Release/MeshNotes.app \
    build/MeshNotes-1.0.0.dmg \
    1.0.0
```

**Features:**
- Automatically reads version from `pubspec.yaml`
- Creates DMG with app and Applications symlink
- Sets DMG window layout and icon size
- Compresses DMG to reduce file size
- Handles mount point detection for different filesystem types (HFS+, APFS)

**Implementation Details:**

The script:
1. Validates the app bundle exists
2. Creates a temporary directory structure
3. Copies the app and creates Applications symlink
4. Creates a temporary DMG using `hdiutil create`
5. Mounts the DMG and configures window layout via AppleScript
6. Unmounts and compresses to final DMG format (UDZO)

**Error Handling:**
- Checks for app existence before proceeding
- Robust mount point detection (supports multiple filesystem types)
- Automatic cleanup on exit (unmounts DMG, removes temp files)
- Detailed error messages with debugging information

### sign_and_notarize_dmg.sh - Signing and Notarization Tool

Signs and notarizes a DMG file for macOS distribution.

**Location**: [tools/sign_and_notarize_dmg.sh](../tools/sign_and_notarize_dmg.sh)

**Usage:**
```bash
./tools/sign_and_notarize_dmg.sh <dmg_path> [options]
```

**Required Parameters:**
- `dmg_path` - Path to DMG file to sign and notarize

**Options:**
- `--apple-id` - Apple ID email (or set `APPLE_ID` environment variable)
- `--team-id` - Apple Developer Team ID (or set `TEAM_ID` environment variable)
- `--app-password` - App-specific password (or set `APP_PASSWORD` environment variable)
- `--keychain-profile` - Keychain profile name (default: `meshnotes-notary`)
- `--skip-notarize` - Only sign, skip notarization

**Examples:**
```bash
# Using command-line arguments
./tools/sign_and_notarize_dmg.sh build/MeshNotes-1.0.0.dmg \
    --apple-id your@email.com \
    --team-id ABC123DEFG \
    --app-password xxxx-xxxx-xxxx-xxxx

# Using environment variables
export APPLE_ID=your@email.com
export TEAM_ID=ABC123DEFG
export APP_PASSWORD=xxxx-xxxx-xxxx-xxxx
./tools/sign_and_notarize_dmg.sh build/MeshNotes-1.0.0.dmg
```

**Features:**
- Signs DMG with Developer ID Application certificate
- Submits to Apple notarization service (supports notarytool and altool)
- Automatically waits for notarization to complete
- Staples notarization ticket to DMG

**Implementation Details:**

The script performs three steps:

1. **Signing**: Uses `codesign` with Developer ID Application certificate
   - Automatically detects available certificates
   - Verifies signature after signing

2. **Notarization**: Submits DMG to Apple
   - Prefers `notarytool` (recommended, modern)
   - Falls back to `altool` (deprecated but still supported)
   - Polls for completion (can take 5-30 minutes)
   - Shows progress and status

3. **Stapling**: Attaches notarization ticket
   - Uses `xcrun stapler staple` to attach ticket
   - Validates stapling was successful

**Notarization Methods:**

**notarytool (Recommended):**
- Uses keychain profile for credentials
- Stores credentials securely in keychain
- Better error messages and status reporting

**altool (Legacy):**
- Requires app-specific password
- Uses XML output for status checking
- Still supported but deprecated

## Complete Workflow

### 1. Build Application
```bash
cd /path/to/meshnotes
flutter build macos --release
```

### 2. Create DMG
```bash
./tools/build_dmg.sh
```

Output: `build/MeshNotes-{version}.dmg`

### 3. Sign and Notarize DMG
```bash
# Set environment variables
export APPLE_ID=your@email.com
export TEAM_ID=ABC123DEFG
export APP_PASSWORD=xxxx-xxxx-xxxx-xxxx

# Sign and notarize
./tools/sign_and_notarize_dmg.sh build/MeshNotes-0.3.1.dmg
```

## Prerequisites

### 1. Developer Certificate

Ensure "Developer ID Application" certificate is installed:
```bash
security find-identity -v -p codesigning
```

The certificate should appear in the list with "Developer ID Application" in the name.

### 2. App-Specific Password

For notarytool, create an app-specific password:
1. Visit https://appleid.apple.com
2. Sign in and go to "App-Specific Passwords"
3. Generate a new password
4. Save the password for use with `--app-password` parameter

### 3. Team ID

Find your Team ID in Apple Developer account, or use:
```bash
xcrun altool --list-providers -u your@email.com -p app_password
```

## Notes

1. **Notarization Time**: Notarization can take 5-30 minutes; the script automatically waits for completion
2. **Network Connection**: Notarization requires stable internet connection
3. **Certificate Validity**: Ensure developer certificate is not expired
4. **DMG Optimization**: The `build_dmg.sh` script can be further optimized (custom background images, window sizing, etc.)

## Troubleshooting

### Signing Fails
- Check certificate is correctly installed: `security find-identity -v -p codesigning`
- Ensure certificate type is "Developer ID Application"
- Verify certificate is not expired

### Notarization Fails
- Check Apple ID and password are correct
- View detailed logs: `xcrun notarytool log <submission-id> --keychain-profile <profile>`
- Ensure app is correctly signed before notarization
- Check Apple Developer account status

### DMG Won't Open
- Check signature: `codesign --verify --verbose <dmg_path>`
- Check notarization status: `spctl -a -v -t install <dmg_path>`
- Verify stapling: `xcrun stapler validate <dmg_path>`

### Mount Point Detection Issues
If `build_dmg.sh` fails to find mount point:
- Check `hdiutil attach` output format
- Verify filesystem type (HFS+, APFS)
- Check `/Volumes/` directory for mounted volumes
- Script includes detailed debugging output for diagnosis

## Future Improvements

The `build_dmg.sh` script is designed to be modular and can be enhanced with:
- Custom DMG background images
- Custom window sizes and positions
- Custom volume icons
- Additional DMG metadata
- Support for different DMG formats

