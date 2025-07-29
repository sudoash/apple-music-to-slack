#!/bin/bash

# Build script to create Apple Music to Slack.app bundle

set -e

APP_NAME="Apple Music to Slack"
BUNDLE_NAME="${APP_NAME}.app"
BUILD_DIR="build"
EXECUTABLE_NAME="apple-music-to-slack"

echo "Building ${APP_NAME}..."

# Clean previous builds
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Build the executable in release mode
swift build -c release

# Create app bundle structure
APP_BUNDLE="${BUILD_DIR}/${BUNDLE_NAME}"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy the executable
cp ".build/release/${EXECUTABLE_NAME}" "${MACOS_DIR}/${EXECUTABLE_NAME}"

# Make executable
chmod +x "${MACOS_DIR}/${EXECUTABLE_NAME}"

# Copy Info.plist
cp "Sources/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Copy app icon if it exists
echo "Adding app icon..."
cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

# Copy status icons
echo "Adding status icons..."
cp "Resources/statusicon-playing-v1.png" "${RESOURCES_DIR}/statusicon-playing-v1.png"
cp "Resources/statusicon-stopped-v1.png" "${RESOURCES_DIR}/statusicon-stopped-v1.png"

# Create PkgInfo file
echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo "✅ Successfully created ${BUNDLE_NAME} in ${BUILD_DIR}/"
echo "You can now:"
echo "  1. Copy ${BUILD_DIR}/${BUNDLE_NAME} to /Applications/"
echo "  2. Or run: cp -r \"${BUILD_DIR}/${BUNDLE_NAME}\" /Applications/"
