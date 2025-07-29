#!/bin/bash

# Script to create app icon from a source image
# Usage: ./create_icon.sh source_image.png

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <source_image.png>"
    echo ""
    echo "Creates an .icns file from a source PNG image (should be at least 1024x1024)"
    echo "The source image should be a square PNG with transparent background"
    exit 1
fi

SOURCE_IMAGE="$1"
ICON_NAME="AppIcon"
ICONSET_DIR="${ICON_NAME}.iconset"

if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "Error: Source image '$SOURCE_IMAGE' not found"
    exit 1
fi

echo "Creating icon set from $SOURCE_IMAGE..."

# Create iconset directory
mkdir -p "$ICONSET_DIR"

# Generate all required icon sizes
# macOS requires specific sizes for .icns files
declare -a sizes=(
    "16x16"
    "16x16@2x:32x32"
    "32x32" 
    "32x32@2x:64x64"
    "128x128"
    "128x128@2x:256x256"
    "256x256"
    "256x256@2x:512x512"
    "512x512"
    "512x512@2x:1024x1024"
)

for size_spec in "${sizes[@]}"; do
    if [[ $size_spec == *"@2x:"* ]]; then
        # Handle @2x cases
        name=$(echo $size_spec | cut -d: -f1)
        actual_size=$(echo $size_spec | cut -d: -f2)
    else
        name="$size_spec"
        actual_size="$size_spec"
    fi
    
    width=$(echo $actual_size | cut -dx -f1)
    
    echo "  Generating icon_${name}.png (${actual_size})"
    sips -z $width $width "$SOURCE_IMAGE" --out "${ICONSET_DIR}/icon_${name}.png" >/dev/null 2>&1
done

# Convert iconset to icns
echo "Converting to .icns format..."
iconutil -c icns "$ICONSET_DIR"

# Clean up iconset directory
rm -rf "$ICONSET_DIR"

echo "✅ Created ${ICON_NAME}.icns"
echo "Icon file is ready to be included in your app bundle"

mv "${ICON_NAME}.icns" "Resources/AppIcon.icns"
echo "Icon file moved to Resources directory"
