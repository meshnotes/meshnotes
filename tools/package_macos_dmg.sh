#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENTITLEMENTS="$PROJECT_ROOT/macos/Runner/Release.entitlements"
DEFAULT_ENV_FILE="$PROJECT_ROOT/.env.notarize"
DEFAULT_APP_NAME="MeshNotes"

ENV_FILE="$DEFAULT_ENV_FILE"
SKIP_BUILD=0
SKIP_NOTARIZE=0
DRY_RUN=0

usage() {
  cat <<EOF
Build and package the macOS MeshNotes app into a signed DMG, then optionally submit it for Apple notarization.

Usage:
  $0 [options]

Options:
  --env-file PATH      Signing/notarization env file (default: .env.notarize)
  --skip-build         Reuse an existing release MeshNotes.app
  --skip-notarize      Sign the app and DMG without calling Apple's notary service
  --dry-run            Check tools, configuration, and inputs without building, signing, or submitting
  -h, --help           Show this help

Secrets are read only from the gitignored env file, never from command-line options.
See .env.notarize.example and documentation/08-tools.md.
EOF
}

require_option_value() {
  local option="$1"
  local value="${2:-}"
  if [ -z "$value" ] || [[ "$value" == --* ]]; then
    echo "Option $option requires a value." >&2
    usage >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --env-file)
      require_option_value "$1" "${2:-}"
      ENV_FILE="$2"
      shift 2
      ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --skip-notarize) SKIP_NOTARIZE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script only runs on macOS." >&2
  exit 2
fi

REAL_HOME="$(eval echo "~$(id -un)")"
if [ -d "$REAL_HOME" ] && [ "$HOME" != "$REAL_HOME" ] && [ ! -f "$HOME/Library/Keychains/login.keychain-db" ]; then
  echo "Using macOS user home for keychain-sensitive tools: $REAL_HOME"
  export HOME="$REAL_HOME"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 2
  fi
}

require_xcrun_tool() {
  if ! xcrun --find "$1" >/dev/null 2>&1; then
    echo "Required Xcode command not found: $1" >&2
    exit 2
  fi
}

require_cmd fvm
require_cmd hdiutil
require_cmd codesign
require_cmd ditto
require_cmd security
if [ "$SKIP_NOTARIZE" -eq 0 ]; then
  require_cmd xcrun
  require_xcrun_tool notarytool
  require_xcrun_tool stapler
fi

load_env_file() {
  local file="$1"
  local line key value
  if [ ! -f "$file" ]; then
    echo "Signing/notarization env file not found: $file" >&2
    echo "Copy $PROJECT_ROOT/.env.notarize.example to $file and fill in the required values." >&2
    exit 2
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      ''|\#*) continue ;;
    esac
    if [[ "$line" != *=* ]]; then
      echo "Malformed line in $file (expected KEY=VALUE): $line" >&2
      exit 2
    fi
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    case "$key" in
      ''|*[!A-Za-z0-9_]*)
        echo "Invalid variable name in $file: $key" >&2
        exit 2
        ;;
    esac
    if [ "${value#\"}" != "$value" ] && [ "${value%\"}" != "$value" ]; then
      value="${value#\"}"
      value="${value%\"}"
    elif [ "${value#\'}" != "$value" ] && [ "${value%\'}" != "$value" ]; then
      value="${value#\'}"
      value="${value%\'}"
    fi
    export "$key=$value"
  done < "$file"
}

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required variable $name in $ENV_FILE" >&2
    exit 2
  fi
}

validate_codesign_identity() {
  local identity="$1"
  if ! security find-identity -v -p codesigning | grep -F -- "$identity" >/dev/null; then
    echo "Codesign identity not found in the current macOS keychain: $identity" >&2
    echo "Check with: security find-identity -v -p codesigning" >&2
    exit 2
  fi
}

preflight_codesign_identity() {
  local identity="$1"
  local temporary_binary
  temporary_binary="$(mktemp "${TMPDIR:-/tmp}/meshnotes-codesign-preflight.XXXXXX")"
  cp /usr/bin/true "$temporary_binary"
  chmod +x "$temporary_binary"
  if ! codesign --force --options runtime --timestamp --sign "$identity" "$temporary_binary"; then
    rm -f "$temporary_binary"
    echo "The identity exists, but codesign cannot use its private key: $identity" >&2
    echo "Unlock the login keychain and confirm the certificate has its private key." >&2
    exit 2
  fi
  codesign --verify --strict "$temporary_binary"
  rm -f "$temporary_binary"
}

NOTARY_ARGS=()

fill_notary_args() {
  NOTARY_ARGS=()
  if [ -n "${MACOS_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
    NOTARY_ARGS=(--keychain-profile "$MACOS_NOTARY_KEYCHAIN_PROFILE")
    return
  fi
  if [ -n "${APPLE_API_KEY_PATH:-}" ] || [ -n "${APPLE_API_KEY_ID:-}" ] || [ -n "${APPLE_API_ISSUER:-}" ]; then
    require_var APPLE_API_KEY_PATH
    require_var APPLE_API_KEY_ID
    require_var APPLE_API_ISSUER
    if [ ! -f "$APPLE_API_KEY_PATH" ]; then
      echo "APPLE_API_KEY_PATH is not a file: $APPLE_API_KEY_PATH" >&2
      exit 2
    fi
    NOTARY_ARGS=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER")
    return
  fi
  require_var APPLE_ID
  require_var APPLE_APP_SPECIFIC_PASSWORD
  require_var APPLE_TEAM_ID
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
}

sign_macho() {
  codesign --force --options runtime --timestamp --sign "$MACOS_CODESIGN_IDENTITY" "$1"
}

sign_app_bundle() {
  local app="$1"
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    sign_macho "$path"
  done < <(find "$app" -type f \( -name "*.dylib" -o -name "*.so" \) | LC_ALL=C sort)

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    sign_macho "$path"
  done < <(find "$app" -name "*.framework" -type d | awk '{ print length($0), $0 }' | LC_ALL=C sort -nr | cut -d' ' -f2-)

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    sign_macho "$path"
  done < <(find "$app" -name "*.appex" -type d | awk '{ print length($0), $0 }' | LC_ALL=C sort -nr | cut -d' ' -f2-)

  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$MACOS_CODESIGN_IDENTITY" "$app"
  codesign --verify --strict --verbose=2 "$app"
}

APP_NAME="$DEFAULT_APP_NAME"
APP_BUNDLE="$PROJECT_ROOT/build/macos/Build/Products/Release/${APP_NAME}.app"
DIST_DIR="$PROJECT_ROOT/dist"
ARCH="$(uname -m)"

if [ "$DRY_RUN" -eq 1 ] && [ ! -f "$ENV_FILE" ]; then
  echo "Dry run: env file missing ($ENV_FILE)."
  echo "Copy .env.notarize.example to .env.notarize and configure the signing identity and one notary authentication method."
  echo "Build command: fvm flutter build macos --release"
  echo "Expected app: $APP_BUNDLE"
  echo "Entitlements: $ENTITLEMENTS"
  exit 0
fi

load_env_file "$ENV_FILE"
APP_NAME="${MACOS_APP_NAME:-$DEFAULT_APP_NAME}"
APP_BUNDLE="$PROJECT_ROOT/build/macos/Build/Products/Release/${APP_NAME}.app"
BUNDLE_ID="${MACOS_BUNDLE_ID:-xyz.meshnotes.meshnotes}"

require_var MACOS_CODESIGN_IDENTITY
if [ "$MACOS_CODESIGN_IDENTITY" = "-" ]; then
  echo "MACOS_CODESIGN_IDENTITY cannot be ad-hoc '-'. Use a Developer ID Application certificate." >&2
  exit 2
fi
validate_codesign_identity "$MACOS_CODESIGN_IDENTITY"
preflight_codesign_identity "$MACOS_CODESIGN_IDENTITY"
if [ ! -f "$ENTITLEMENTS" ]; then
  echo "Release entitlements not found: $ENTITLEMENTS" >&2
  exit 2
fi
if [ "$SKIP_NOTARIZE" -eq 0 ]; then
  fill_notary_args
fi

echo "Project root:    $PROJECT_ROOT"
echo "Env file:       $ENV_FILE"
echo "Codesign:       $MACOS_CODESIGN_IDENTITY"
echo "Bundle ID:      $BUNDLE_ID"
echo "Skip build:     $SKIP_BUILD"
echo "Skip notarize:  $SKIP_NOTARIZE"

if [ "$DRY_RUN" -eq 1 ]; then
  if [ "$SKIP_NOTARIZE" -eq 1 ]; then
    echo "Dry run: would build unless --skip-build, sign $APP_BUNDLE, and create a signed DMG under $DIST_DIR without notarizing it."
  else
    echo "Dry run: would build unless --skip-build, sign $APP_BUNDLE, create a signed DMG under $DIST_DIR, and submit it for notarization."
  fi
  if [ "$SKIP_BUILD" -eq 1 ] && [ ! -d "$APP_BUNDLE" ]; then
    echo "Dry run warning: --skip-build set but app bundle is missing: $APP_BUNDLE" >&2
  fi
  exit 0
fi

if [ "$SKIP_BUILD" -eq 0 ]; then
  echo "Building the macOS release app ..."
  (cd "$PROJECT_ROOT" && fvm flutter build macos --release)
else
  echo "Skipping Flutter build."
fi

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Release app bundle not found: $APP_BUNDLE" >&2
  echo "Run without --skip-build after fixing the build, or provide an existing release build." >&2
  exit 2
fi

ACTUAL_BUNDLE_ID="$(/usr/bin/defaults read "$APP_BUNDLE/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
if [ "$ACTUAL_BUNDLE_ID" != "$BUNDLE_ID" ]; then
  echo "Unexpected app bundle identifier: ${ACTUAL_BUNDLE_ID:-<missing>} (expected $BUNDLE_ID)" >&2
  echo "Set MACOS_BUNDLE_ID only when intentionally packaging a differently configured app." >&2
  exit 2
fi

echo "Signing $APP_BUNDLE ..."
sign_app_bundle "$APP_BUNDLE"

VERSION="$(/usr/bin/defaults read "$APP_BUNDLE/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")"
DMG_NAME="${APP_NAME}-${VERSION}-macos-${ARCH}.dmg"
mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/meshnotes-macos-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

echo "Staging DMG contents in $STAGE ..."
ditto "$APP_BUNDLE" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"

echo "Creating $DMG_PATH ..."
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH"

echo "Signing DMG ..."
codesign --force --timestamp --sign "$MACOS_CODESIGN_IDENTITY" "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"

if [ "$SKIP_NOTARIZE" -eq 1 ]; then
  echo "Skipping notarization. Signed DMG: $DMG_PATH"
  exit 0
fi

echo "Submitting DMG to Apple's notarization service (this can take several minutes) ..."
fill_notary_args
set +e
xcrun notarytool submit "$DMG_PATH" --wait "${NOTARY_ARGS[@]}"
NOTARY_EXIT=$?
set -e
if [ "$NOTARY_EXIT" -ne 0 ]; then
  echo "Notarization did not succeed. Use the submission ID printed above with 'xcrun notarytool log' and the same authentication method." >&2
  exit "$NOTARY_EXIT"
fi

echo "Stapling the notarization ticket ..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "Done."
echo "DMG: $DMG_PATH"
