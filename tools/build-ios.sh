#!/usr/bin/env bash
# Generate and build an iOS Xcode project with source-built static dependencies.
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: tools/build-ios.sh [simulator|device] [extra CMake configure arguments...]

Requires macOS, full Xcode, and CMake 3.29 or newer.
Builds Release by default. Device builds are unsigned unless a Team is supplied.

Environment:
  CONFIGURATION         Release (default), Debug, RelWithDebInfo, or MinSizeRel
  IOS_DEVELOPMENT_TEAM  Apple Team ID; enables automatic signing for device builds
  IOS_ARCH              arm64 for device; host architecture for simulator
  IOS_BUILD_DIR         Override build/ios-device or build/ios-simulator
  IOS_AFS_FILE          Optional local SF33RD.AFS to verify and bundle in the app
  BUILD_JOBS            Number of parallel build jobs (default: 4)

Unsigned device IPA: build/ios-device/3SX-unsigned.ipa
USAGE
}
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    usage
    exit 0
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${1:-simulator}"
CONFIGURATION="${CONFIGURATION:-Release}"

if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null 2>&1; then
    echo "An iOS build requires macOS and the full Xcode application." >&2
    exit 1
fi
if ! command -v cmake >/dev/null 2>&1; then
    echo "Install CMake 3.29 or newer (for example, brew install cmake)." >&2
    exit 1
fi

case "$SDK" in
    simulator)
        SYSROOT=iphonesimulator
        ARCH="${IOS_ARCH:-$(uname -m)}"
        ;;
    device)
        SYSROOT=iphoneos
        ARCH="${IOS_ARCH:-arm64}"
        ;;
    *)
        usage >&2
        exit 1
        ;;
esac
if [[ $# -gt 0 ]]; then shift; fi

xcrun --sdk "$SYSROOT" --show-sdk-path >/dev/null
BUILD_DIR="${IOS_BUILD_DIR:-$ROOT_DIR/build/ios-$SDK}"
SIGN=OFF
if [[ "$SDK" == device && -n "${IOS_DEVELOPMENT_TEAM:-}" ]]; then SIGN=ON; fi

cmake -S "$ROOT_DIR" -B "$BUILD_DIR" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$SYSROOT" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DTHREESX_IOS_SIGN="$SIGN" \
    -DTHREESX_IOS_DEVELOPMENT_TEAM="${IOS_DEVELOPMENT_TEAM:-}" \
    -DTHREESX_IOS_AFS_FILE:FILEPATH="${IOS_AFS_FILE:-}" \
    "$@"
cmake --build "$BUILD_DIR" --config "$CONFIGURATION" --target 3sx --parallel "${BUILD_JOBS:-4}"

echo "App: $BUILD_DIR/$CONFIGURATION-$SYSROOT/3SX.app"
echo "Xcode project: $BUILD_DIR/3sx.xcodeproj"
if [[ "$SDK" == device && "$SIGN" == OFF ]]; then
    # A signer on Windows or another supported platform can consume this IPA.
    # Package the built app, including game data only when explicitly supplied
    # using IOS_AFS_FILE or THREESX_IOS_AFS_FILE during configuration.
    PACKAGE_DIR="$(mktemp -d)"
    trap 'rm -rf "$PACKAGE_DIR"' EXIT
    mkdir -p "$PACKAGE_DIR/Payload"
    ditto "$BUILD_DIR/$CONFIGURATION-$SYSROOT/3SX.app" "$PACKAGE_DIR/Payload/3SX.app"
    ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR/Payload" "$BUILD_DIR/3SX-unsigned.ipa"
    echo "Unsigned IPA: $BUILD_DIR/3SX-unsigned.ipa"
    cp "$ROOT_DIR/tools/personalize-ios-ipa.py" "$BUILD_DIR/personalize-ios-ipa.py"
    cat > "$BUILD_DIR/INSTALL.txt" <<'INSTALL'
3SX iOS

1. Sign and install 3SX-unsigned.ipa with iLoader or your sideloading tool.
2. Transfer the extracted SF33RD.AFS to Files on your phone.
3. Open 3SX, tap Import SF33RD.AFS, and select it.

Tap the gear in the top right for iOS options. Settings save automatically.
The gear hides after five idle seconds; touch the screen to reveal it.
Choose Hybrid, Stick or D-pad, or open Edit controls & custom buttons.
Drag controls to move them; tap for size/position; Add creates button chords.
Display settings include independent width/height stretching and CRT filters.
Update the existing app using the same signing account to retain game data.

Optional PERSONAL icon (the public app contains no personal icon):
Install Python and Pillow: py -3 -m pip install pillow
Run: py -3 personalize-ios-ipa.py
The file pickers ask for the downloaded IPA, your local icon, and an output.
Sign and install the resulting private IPA. No image is uploaded by this tool.
INSTALL
    echo "Sign the IPA with your sideloading tool before installing it on a device."
fi
