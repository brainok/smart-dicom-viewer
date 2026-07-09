#!/bin/bash
# Builds a signed, Finder-laid-out DMG with a white background and centered install arrow.
set -euo pipefail

EXECUTABLE_NAME="OpenDicomViewer"
APP_NAME="Smart DICOM Viewer"
VERSION="v2.02"
APP_BUNDLE="${APP_NAME}.app"
RELEASE_DIR="release/${VERSION}"
DMG_NAME="${APP_NAME} v2.0.dmg"
DMG_PATH="${RELEASE_DIR}/${DMG_NAME}"
STAGING_DIR="build/dmg-staging"
ASSETS_DIR="build/dmg-assets"
BACKGROUND_PATH="${ASSETS_DIR}/background.png"
SIGNING_IDENTITY="Developer ID Application: HYO SUK NAM (FC724Q48DM)"
APPLE_ID="brainok777@gmail.com"
TEAM_ID="FC724Q48DM"

WINDOW_WIDTH=900
WINDOW_HEIGHT=700
ICON_Y=330
APP_X=250
APPLICATIONS_X=650
ICON_SIZE=160

cd "$(dirname "$0")/.."

echo "Building ${APP_NAME}..."
swift build -c release --arch arm64

echo "Creating ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp ".build/release/${EXECUTABLE_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
cp "libs/dcmtk/share/dcmtk-3.6.8/dicom.dic" "${APP_BUNDLE}/Contents/Resources/"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
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
    <string>2.02</string>
    <key>CFBundleVersion</key>
    <string>202</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
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

echo "Signing app with Developer ID..."
codesign --force --options runtime --timestamp \
    --entitlements scripts/OpenDicomViewer.entitlements \
    --sign "${SIGNING_IDENTITY}" \
    "${APP_BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "Rendering DMG background..."
swift scripts/render_dmg_background.swift "${BACKGROUND_PATH}"

echo "Creating pretty DMG..."
mkdir -p "${RELEASE_DIR}"
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"

create-dmg \
    --volname "${APP_NAME}" \
    --volicon "AppIcon.icns" \
    --background "${BACKGROUND_PATH}" \
    --window-pos 200 120 \
    --window-size "${WINDOW_WIDTH}" "${WINDOW_HEIGHT}" \
    --text-size 14 \
    --icon-size "${ICON_SIZE}" \
    --icon "${APP_BUNDLE}" "${APP_X}" "${ICON_Y}" \
    --hide-extension "${APP_BUNDLE}" \
    --app-drop-link "${APPLICATIONS_X}" "${ICON_Y}" \
    --no-internet-enable \
    --format UDZO \
    --filesystem HFS+ \
    --codesign "${SIGNING_IDENTITY}" \
    "${DMG_PATH}" \
    "${STAGING_DIR}"

if [[ -f "Smart-dicom-viewer-icon.png" ]] &&
   command -v sips >/dev/null 2>&1 &&
   command -v DeRez >/dev/null 2>&1 &&
   command -v Rez >/dev/null 2>&1 &&
   command -v SetFile >/dev/null 2>&1; then
    echo "Applying custom Finder icon to DMG file..."
    DMG_ICON_TMP_DIR="$(mktemp -d)"
    DMG_ICON_PNG="${DMG_ICON_TMP_DIR}/DmgIcon.png"
    DMG_ICON_RSRC="${DMG_ICON_TMP_DIR}/DmgIcon.rsrc"
    sips -z 512 512 "Smart-dicom-viewer-icon.png" --out "${DMG_ICON_PNG}" >/dev/null
    sips -i "${DMG_ICON_PNG}" >/dev/null
    DeRez -only icns "${DMG_ICON_PNG}" > "${DMG_ICON_RSRC}"
    Rez -append "${DMG_ICON_RSRC}" -o "${DMG_PATH}"
    SetFile -a C "${DMG_PATH}"
    rm -rf "${DMG_ICON_TMP_DIR}"
fi

echo "Signing DMG..."
codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"
hdiutil verify "${DMG_PATH}"

if [[ "${NOTARY_PASSWORD:-}" != "" ]]; then
    echo "Submitting DMG for notarization..."
    xcrun notarytool submit "${DMG_PATH}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${TEAM_ID}" \
        --password "${NOTARY_PASSWORD}" \
        --wait
    xcrun stapler staple "${DMG_PATH}"
    spctl --assess --type open --context context:primary-signature -vv "${DMG_PATH}"
else
    echo "NOTARY_PASSWORD is not set; skipping notarization."
fi

echo "Created ${DMG_PATH}"
