#!/bin/bash
# package_app.sh — OpenDicomViewer
# Builds a release binary and creates the .app bundle + DMG for distribution.
# Use --notarize to sign with Developer ID and notarize with Apple.
# Licensed under the MIT License. See LICENSE for details.
set -e

EXECUTABLE_NAME="OpenDicomViewer"
APP_NAME="Smart DICOM Viewer"
RELEASE_DIR="Release/v2.03"
SIGNING_IDENTITY="Developer ID Application: HYO SUK NAM (FC724Q48DM)"
NOTARY_PROFILE="OpenDicomViewer"
NOTARIZE=false

if [[ "$1" == "--notarize" ]]; then
    NOTARIZE=true
fi

# Ensure we are in project root
cd "$(dirname "$0")/.."

echo "Building ${APP_NAME} (Release)..."
swift build -c release --arch arm64

BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Creating App Bundle at ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "Copying Executable..."
cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${MACOS_DIR}/"

echo "Copying App Icon..."
cp "AppIcon.icns" "${RESOURCES_DIR}/"

echo "Copying DCMTK Dictionary..."
cp "libs/dcmtk/share/dcmtk-3.6.8/dicom.dic" "${RESOURCES_DIR}/"

echo "Creating Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.smartdicomviewer.app</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.03</string>
    <key>CFBundleVersion</key>
    <string>203</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>DICOM File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>dcm</string>
                <string>dicom</string>
                <string>ima</string>
            </array>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.data</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>DICOM Folder</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.folder</string>
            </array>
        </dict>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Smart DICOM Viewer needs access to open DICOM files.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Smart DICOM Viewer needs access to open DICOM files.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Smart DICOM Viewer needs access to open DICOM files.</string>
</dict>
</plist>
EOF

if $NOTARIZE; then
    echo "Code signing with Developer ID..."
    codesign --force --options runtime --sign "${SIGNING_IDENTITY}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
    codesign --force --options runtime --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
    codesign --verify --deep --strict "${APP_BUNDLE}"
    echo "Signature OK"
else
    echo "Ad-hoc code signing (use --notarize for Developer ID signing)..."
    codesign --force --deep -s - "${APP_BUNDLE}"
fi

echo "Successfully created ${APP_BUNDLE}"

# --- Create DMG for distribution ---
mkdir -p "${RELEASE_DIR}"
DMG_NAME="${RELEASE_DIR}/Smart-DICOM-Viewer.dmg"
DMG_TEMP="dmg_tmp"

echo "Creating DMG at ${DMG_NAME}..."
rm -rf "${DMG_TEMP}" "${DMG_NAME}"
mkdir -p "${DMG_TEMP}"

cp -R "${APP_BUNDLE}" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${DMG_NAME}" \
    -quiet

rm -rf "${DMG_TEMP}"

if command -v sips >/dev/null 2>&1 &&
   command -v DeRez >/dev/null 2>&1 &&
   command -v Rez >/dev/null 2>&1 &&
   command -v SetFile >/dev/null 2>&1 &&
   [[ -f "Smart-dicom-viewer-icon.png" ]]; then
    echo "Applying custom DMG icon..."
    DMG_ICON_TMP_DIR="$(mktemp -d)"
    DMG_ICON_PNG="${DMG_ICON_TMP_DIR}/DmgIcon.png"
    DMG_ICON_RSRC="${DMG_ICON_TMP_DIR}/DmgIcon.rsrc"
    sips -z 512 512 "Smart-dicom-viewer-icon.png" --out "${DMG_ICON_PNG}" >/dev/null
    sips -i "${DMG_ICON_PNG}" >/dev/null
    DeRez -only icns "${DMG_ICON_PNG}" > "${DMG_ICON_RSRC}"
    Rez -append "${DMG_ICON_RSRC}" -o "${DMG_NAME}"
    SetFile -a C "${DMG_NAME}"
    rm -rf "${DMG_ICON_TMP_DIR}"
fi

if $NOTARIZE; then
    echo "Submitting ${DMG_NAME} for notarization..."
    xcrun notarytool submit "${DMG_NAME}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "${DMG_NAME}"

    echo ""
    echo "Successfully created and notarized ${DMG_NAME}"
else
    echo ""
    echo "Successfully created ${DMG_NAME} (not notarized)"
fi
echo "To install: open ${DMG_NAME} and drag ${APP_NAME} to Applications"
