#!/bin/bash

# build_dmg.sh - Create macOS DMG installer package
#
# Usage:
#   ./build_dmg.sh [app_path] [output_dmg_path] [version]
#
# Parameters:
#   app_path        - Path to MeshNotes.app (default: build/macos/Build/Products/Release/MeshNotes.app)
#   output_dmg_path - Output DMG file path (default: build/MeshNotes-{version}.dmg)
#   version         - Version number (default: read from pubspec.yaml)
#
# Examples:
#   ./build_dmg.sh
#   ./build_dmg.sh build/macos/Build/Products/Release/MeshNotes.app dist/MeshNotes-1.0.0.dmg 1.0.0

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default parameters
DEFAULT_APP_PATH="$PROJECT_ROOT/build/macos/Build/Products/Release/MeshNotes.app"
DEFAULT_VERSION=$(grep "^version:" "$PROJECT_ROOT/pubspec.yaml" | sed 's/version: //' | sed 's/+.*//')

# Parse parameters
APP_PATH="${1:-$DEFAULT_APP_PATH}"
VERSION="${3:-$DEFAULT_VERSION}"
OUTPUT_DMG="${2:-$PROJECT_ROOT/build/MeshNotes-${VERSION}.dmg}"

# Convert to absolute paths
if [ -f "$APP_PATH" ] || [ -d "$APP_PATH" ]; then
    APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
else
    # If path doesn't exist, try to convert to absolute path (for checking)
    APP_DIR="$(cd "$(dirname "$APP_PATH")" 2>/dev/null && pwd || echo "$(dirname "$APP_PATH")")"
    APP_PATH="$APP_DIR/$(basename "$APP_PATH")"
fi

# Ensure output directory exists
OUTPUT_DIR="$(dirname "$OUTPUT_DMG")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DMG="$(cd "$OUTPUT_DIR" && pwd)/$(basename "$OUTPUT_DMG")"

echo -e "${GREEN}Starting DMG build...${NC}"
echo "App path: $APP_PATH"
echo "Output DMG: $OUTPUT_DMG"
echo "Version: $VERSION"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: App not found: $APP_PATH${NC}"
    echo "Please run: flutter build macos --release"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
DMG_MOUNT_DIR="$TEMP_DIR/dmg"
DMG_TEMP="$TEMP_DIR/MeshNotes-temp.dmg"

# Cleanup function
cleanup() {
    # Unmount DMG if mounted
    if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
        hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    fi
    if [ -n "$DEVICE" ]; then
        hdiutil detach "$DEVICE" -quiet 2>/dev/null || true
    fi
    # Clean up temporary directory
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Create DMG mount directory
mkdir -p "$DMG_MOUNT_DIR"

# Copy app to DMG directory
echo -e "${GREEN}Copying app to DMG...${NC}"
cp -R "$APP_PATH" "$DMG_MOUNT_DIR/"

# Create Applications folder symlink
echo -e "${GREEN}Creating Applications link...${NC}"
ln -s /Applications "$DMG_MOUNT_DIR/Applications"

# Set DMG window size and layout
# Calculate required size (MB)
APP_SIZE=$(du -sm "$APP_PATH" | cut -f1)
DMG_SIZE=$((APP_SIZE + 50)) # Extra 50MB space

echo -e "${GREEN}Creating temporary DMG file...${NC}"
hdiutil create -srcfolder "$DMG_MOUNT_DIR" \
    -volname "MeshNotes" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size ${DMG_SIZE}m \
    "$DMG_TEMP"

# Mount temporary DMG
echo -e "${GREEN}Mounting temporary DMG...${NC}"
ATTACH_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP" 2>&1)

# Extract device path and mount point from output
# hdiutil attach output format may be:
# /dev/diskXsY  /Volumes/VolumeName
# or
# /dev/diskXsY              /Volumes/VolumeName
DEVICE=$(echo "$ATTACH_OUTPUT" | grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT_POINT=$(echo "$ATTACH_OUTPUT" | grep -E '^/dev/' | head -1 | awk '{print $NF}')

# If not found from attach output, try getting from hdiutil info
if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    echo -e "${YELLOW}Mount point not found in attach output, trying hdiutil info...${NC}"
    sleep 2
    if [ -n "$DEVICE" ]; then
        # Try multiple filesystem types
        MOUNT_POINT=$(hdiutil info | grep "$DEVICE" | grep -E "(Apple_HFS|APFS|HFS\+)" | awk '{print $NF}' | head -1)
    fi
fi

# If still not found, try finding from /Volumes directory
if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    echo -e "${YELLOW}Trying to find mount point from /Volumes...${NC}"
    # Find recently mounted MeshNotes volume
    MOUNT_POINT=$(ls -td /Volumes/MeshNotes* 2>/dev/null | head -1)
fi

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    echo -e "${RED}Error: Unable to find mount point${NC}"
    echo "Device: $DEVICE"
    echo "Mount point: $MOUNT_POINT"
    echo "hdiutil attach output:"
    echo "$ATTACH_OUTPUT"
    echo ""
    echo "Currently mounted volumes:"
    ls -la /Volumes/ 2>/dev/null || true
    exit 1
fi

echo "Mount point: $MOUNT_POINT"

# Set DMG window properties
echo -e "${GREEN}Setting DMG window properties...${NC}"

# Use AppleScript to set window layout
osascript <<EOF
tell application "Finder"
    tell disk "MeshNotes"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 920, 420}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 72
        set position of item "MeshNotes.app" of container window to {160, 205}
        set position of item "Applications" of container window to {360, 205}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
EOF

# Sync filesystem
sync

# Unmount DMG
echo -e "${GREEN}Unmounting temporary DMG...${NC}"
hdiutil detach "$MOUNT_POINT" -quiet || hdiutil detach "$DEVICE" -quiet

# Compress and convert to final DMG
echo -e "${GREEN}Compressing DMG...${NC}"
hdiutil convert "$DMG_TEMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$OUTPUT_DMG"

# Set DMG permissions
chmod 644 "$OUTPUT_DMG"

echo -e "${GREEN}✓ DMG build complete: $OUTPUT_DMG${NC}"
echo -e "${GREEN}File size: $(du -h "$OUTPUT_DMG" | cut -f1)${NC}"
