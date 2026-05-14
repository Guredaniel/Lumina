#!/bin/bash

# PhotoViewer Build Script
# Usage: ./build.sh [debug|release]

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

BUILD_CONFIG="${1:-release}"
BUILD_CONFIG="$(echo "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]')"  # Convert to lowercase

if [ "$BUILD_CONFIG" != "debug" ] && [ "$BUILD_CONFIG" != "release" ]; then
    echo "Usage: $0 [debug|release]"
    exit 1
fi

# Convert to title case for display (optional)
BUILD_CONFIG_DISPLAY="$(tr '[:lower:]' '[:upper:]' <<< ${BUILD_CONFIG:0:1})${BUILD_CONFIG:1}"

echo "Building PhotoViewer ($BUILD_CONFIG_DISPLAY)..."

# Check if swift is available
if ! command -v swift &> /dev/null; then
    echo "Error: swift not found. Please install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

# Build the project using Swift Package Manager
echo "Building with Swift Package Manager..."
swift build --configuration "$BUILD_CONFIG"

BUILD_PATH=".build/apple/Products/$BUILD_CONFIG_DISPLAY/PhotoViewer"
if [ ! -x "$BUILD_PATH" ]; then
    BUILD_PATH=".build/$BUILD_CONFIG/PhotoViewer"
fi

if [ -x "$BUILD_PATH" ]; then
    echo "✅ Build successful!"
    echo "Binary location: $BUILD_PATH"
    
    # Create the .app bundle
    APP_BUNDLE_NAME="PhotoViewer.app"
    APP_BUNDLE_PATH="build/${APP_BUNDLE_NAME}"
    echo "Creating macOS App Bundle at ${APP_BUNDLE_PATH}..."
    
    mkdir -p "${APP_BUNDLE_PATH}/Contents/MacOS"
    mkdir -p "${APP_BUNDLE_PATH}/Contents/Resources"
    
    # Copy executable
    cp "$BUILD_PATH" "${APP_BUNDLE_PATH}/Contents/MacOS/"
    
    # Copy Info.plist and resolve variables
    sed -e "s/\$(EXECUTABLE_NAME)/PhotoViewer/g" \
        -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.example.PhotoViewer/g" \
        -e "s/\$(PRODUCT_NAME)/PhotoViewer/g" \
        Info.plist > "${APP_BUNDLE_PATH}/Contents/Info.plist"
    
    # Copy icon file to Resources
    if [ -f "Sources/PhotoViewer/Resources/icon.icns" ]; then
        cp Sources/PhotoViewer/Resources/icon.icns "${APP_BUNDLE_PATH}/Contents/Resources/"
        echo "✅ Icon copied to app bundle"
    fi
        
    echo "✅ App bundle created successfully at ${APP_BUNDLE_PATH}"
    
    # Auto-run for release, prompt for debug
    if [ "$BUILD_CONFIG" = "release" ]; then
        echo "Launching PhotoViewer in release mode..."
        open "${APP_BUNDLE_PATH}"
    else
        read -p "Run the app now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            open "${APP_BUNDLE_PATH}"
        fi
    fi
else
    echo "❌ Build failed or app not found at expected location"
    exit 1
fi
