#!/bin/bash

# Installation script for Apple Music to Slack

set -e

APP_NAME="Apple Music to Slack"
BUNDLE_NAME="${APP_NAME}.app"

echo "🎵 Installing ${APP_NAME}..."

# Check if app bundle exists
if [ ! -d "build/${BUNDLE_NAME}" ]; then
    echo "❌ App bundle not found. Building first..."
    make app
fi

# Check if Applications directory is writable
if [ ! -w "/Applications" ]; then
    echo "❌ Cannot write to /Applications directory."
    echo "💡 Try running with sudo: sudo ./install.sh"
    echo "💡 Or copy manually: cp -r \"build/${BUNDLE_NAME}\" /Applications/"
    exit 1
fi

# Install the app
echo "📦 Copying ${BUNDLE_NAME} to /Applications..."
cp -r "build/${BUNDLE_NAME}" "/Applications/"

echo "✅ Successfully installed ${APP_NAME}!"
echo ""
echo "🚀 You can now:"
echo "   • Find it in your Applications folder"
echo "   • Launch it from Spotlight (⌘+Space)"
echo "   • Run: open \"/Applications/${BUNDLE_NAME}\""
echo ""
echo "⚙️  Don't forget to configure your Slack token first!"
echo "   See README.md for configuration instructions."
