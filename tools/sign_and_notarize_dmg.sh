#!/bin/bash

# sign_and_notarize_dmg.sh - Sign and notarize macOS DMG file
#
# Usage:
#   ./sign_and_notarize_dmg.sh <dmg_path> [options]
#
# Parameters:
#   dmg_path        - Path to DMG file to sign and notarize (required)
#
# Options:
#   --apple-id      - Apple ID email (required, or set APPLE_ID environment variable)
#   --team-id       - Apple Developer Team ID (required, or set TEAM_ID environment variable)
#   --app-password  - App-specific password (required, or set APP_PASSWORD environment variable)
#   --keychain-profile - Keychain profile name for notarytool (default: meshnotes-notary)
#   --skip-notarize - Only sign, skip notarization
#
# Environment Variables:
#   APPLE_ID        - Apple ID email
#   TEAM_ID         - Apple Developer Team ID
#   APP_PASSWORD    - App-specific password (for altool)
#   KEYCHAIN_PROFILE - Keychain profile name (for notarytool)
#
# Examples:
#   ./sign_and_notarize_dmg.sh build/MeshNotes-1.0.0.dmg \
#       --apple-id your@email.com \
#       --team-id ABC123DEFG \
#       --app-password xxxx-xxxx-xxxx-xxxx
#
#   Or using environment variables:
#   export APPLE_ID=your@email.com
#   export TEAM_ID=ABC123DEFG
#   export APP_PASSWORD=xxxx-xxxx-xxxx-xxxx
#   ./sign_and_notarize_dmg.sh build/MeshNotes-1.0.0.dmg

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse parameters
DMG_PATH=""
APPLE_ID="${APPLE_ID:-}"
TEAM_ID="${TEAM_ID:-}"
APP_PASSWORD="${APP_PASSWORD:-}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-meshnotes-notary}"
SKIP_NOTARIZE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --apple-id)
            APPLE_ID="$2"
            shift 2
            ;;
        --team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        --app-password)
            APP_PASSWORD="$2"
            shift 2
            ;;
        --keychain-profile)
            KEYCHAIN_PROFILE="$2"
            shift 2
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        -*)
            echo -e "${RED}Error: Unknown option $1${NC}"
            exit 1
            ;;
        *)
            if [ -z "$DMG_PATH" ]; then
                DMG_PATH="$1"
            else
                echo -e "${RED}Error: Extra argument: $1${NC}"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check required parameters
if [ -z "$DMG_PATH" ]; then
    echo -e "${RED}Error: Please provide DMG file path${NC}"
    echo "Usage: $0 <dmg_path> [options]"
    exit 1
fi

# Convert to absolute path
if [ -f "$DMG_PATH" ]; then
    DMG_PATH="$(cd "$(dirname "$DMG_PATH")" && pwd)/$(basename "$DMG_PATH")"
else
    DMG_DIR="$(cd "$(dirname "$DMG_PATH")" 2>/dev/null && pwd || echo "$(dirname "$DMG_PATH")")"
    DMG_PATH="$DMG_DIR/$(basename "$DMG_PATH")"
fi

# Check if file exists
if [ ! -f "$DMG_PATH" ]; then
    echo -e "${RED}Error: DMG file not found: $DMG_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}Starting DMG signing and notarization...${NC}"
echo "DMG path: $DMG_PATH"

# Check signing tool
if ! command -v codesign &> /dev/null; then
    echo -e "${RED}Error: codesign tool not found${NC}"
    exit 1
fi

# Sign DMG
echo -e "${BLUE}Step 1/3: Signing DMG...${NC}"

# Check for developer certificate
CERT_NAME=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')

if [ -z "$CERT_NAME" ]; then
    echo -e "${YELLOW}Warning: 'Developer ID Application' certificate not found${NC}"
    echo "Please ensure developer certificate is installed, or use the following command to view:"
    echo "  security find-identity -v -p codesigning"
    exit 1
fi

echo "Using certificate: $CERT_NAME"

# Sign DMG
codesign --force --verify --verbose --sign "$CERT_NAME" "$DMG_PATH"

# Verify signature
echo -e "${GREEN}Verifying signature...${NC}"
if codesign --verify --verbose "$DMG_PATH"; then
    echo -e "${GREEN}✓ DMG signed successfully${NC}"
else
    echo -e "${RED}Error: DMG signature verification failed${NC}"
    exit 1
fi

# If skip notarization, exit now
if [ "$SKIP_NOTARIZE" = true ]; then
    echo -e "${GREEN}✓ Signing complete (notarization skipped)${NC}"
    exit 0
fi

# Notarize DMG
echo -e "${BLUE}Step 2/3: Submitting for notarization...${NC}"

# Check notarization tool
if command -v xcrun notarytool &> /dev/null; then
    USE_NOTARYTOOL=true
    echo "Using notarytool (recommended)"
elif command -v xcrun altool &> /dev/null; then
    USE_NOTARYTOOL=false
    echo "Using altool (deprecated, recommend upgrading to notarytool)"
else
    echo -e "${RED}Error: Notarization tool not found (notarytool or altool)${NC}"
    exit 1
fi

if [ "$USE_NOTARYTOOL" = true ]; then
    # Use notarytool (recommended)
    if [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ]; then
        echo -e "${RED}Error: notarytool requires --apple-id and --team-id${NC}"
        echo "Or set environment variables APPLE_ID and TEAM_ID"
        exit 1
    fi

    # Check if keychain profile exists
    if ! xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" &>/dev/null; then
        echo -e "${YELLOW}Configuring keychain profile: $KEYCHAIN_PROFILE${NC}"
        echo "Please enter App-specific password (can be generated at https://appleid.apple.com):"
        xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID"
    fi

    # Submit for notarization
    echo "Submitting to Apple notarization service..."
    SUBMISSION_ID=$(xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait \
        --timeout 30m 2>&1 | grep -i "id:" | head -1 | sed 's/.*[Ii][Dd]: *\([a-f0-9-]*\).*/\1/')

    if [ -z "$SUBMISSION_ID" ]; then
        echo -e "${YELLOW}Waiting for notarization to complete...${NC}"
        xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$KEYCHAIN_PROFILE" \
            --wait \
            --timeout 30m
    fi

    # Check notarization status
    STATUS=$(xcrun notarytool log "$SUBMISSION_ID" \
        --keychain-profile "$KEYCHAIN_PROFILE" 2>&1 | grep -i "status:" | head -1)

    if echo "$STATUS" | grep -qi "accepted"; then
        echo -e "${GREEN}✓ Notarization successful${NC}"
    else
        echo -e "${RED}Error: Notarization failed${NC}"
        echo "Status: $STATUS"
        echo "View logs: xcrun notarytool log $SUBMISSION_ID --keychain-profile $KEYCHAIN_PROFILE"
        exit 1
    fi
else
    # Use altool (deprecated)
    if [ -z "$APPLE_ID" ] || [ -z "$APP_PASSWORD" ]; then
        echo -e "${RED}Error: altool requires --apple-id and --app-password${NC}"
        echo "Or set environment variables APPLE_ID and APP_PASSWORD"
        exit 1
    fi

    echo "Submitting to Apple notarization service..."
    xcrun altool --notarize-app \
        --primary-bundle-id "xyz.meshnotes.meshnotes" \
        --username "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --file "$DMG_PATH" \
        --output-format xml > /tmp/notarize_result.plist

    # Extract UUID
    UUID=$(/usr/libexec/PlistBuddy -c "Print :notarization-upload:RequestUUID" /tmp/notarize_result.plist 2>/dev/null || echo "")

    if [ -z "$UUID" ]; then
        echo -e "${RED}Error: Unable to get notarization UUID${NC}"
        cat /tmp/notarize_result.plist
        exit 1
    fi

    echo "Notarization UUID: $UUID"
    echo -e "${YELLOW}Waiting for notarization to complete (this may take a few minutes)...${NC}"

    # Poll for status
    while true; do
        sleep 30
        xcrun altool --notarization-info "$UUID" \
            --username "$APPLE_ID" \
            --password "$APP_PASSWORD" \
            --output-format xml > /tmp/notarize_status.plist

        STATUS=$(/usr/libexec/PlistBuddy -c "Print :notarization-info:Status" /tmp/notarize_status.plist 2>/dev/null || echo "in progress")

        if [ "$STATUS" = "success" ]; then
            echo -e "${GREEN}✓ Notarization successful${NC}"
            break
        elif [ "$STATUS" = "invalid" ]; then
            echo -e "${RED}Error: Notarization failed${NC}"
            /usr/libexec/PlistBuddy -c "Print :notarization-info:LogFileURL" /tmp/notarize_status.plist
            exit 1
        else
            echo "Notarization status: $STATUS (continuing to wait...)"
        fi
    done
fi

# Staple notarization ticket
echo -e "${BLUE}Step 3/3: Stapling notarization ticket...${NC}"
xcrun stapler staple "$DMG_PATH"

# Verify stapling
if xcrun stapler validate "$DMG_PATH"; then
    echo -e "${GREEN}✓ Notarization ticket stapled successfully${NC}"
else
    echo -e "${YELLOW}Warning: Notarization ticket stapling verification failed, but DMG may still be valid${NC}"
fi

echo -e "${GREEN}✓ Signing and notarization complete: $DMG_PATH${NC}"
