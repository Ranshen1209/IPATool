#!/bin/zsh

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <app-path> <version> [output-dir]" >&2
  exit 1
fi

APP_PATH="$1"
VERSION="$2"
OUTPUT_DIR="${3:-$(pwd)/.build-artifacts}"

APP_NAME="$(basename "$APP_PATH" .app)"
DMG_NAME="${APP_NAME}-v${VERSION}-macOS.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-dmg.XXXXXX")"
ICONSET_DIR="${WORK_DIR}/VolumeIcon.iconset"
STAGING_DIR="${WORK_DIR}/dmg-root"
RW_DMG_PATH="${WORK_DIR}/${APP_NAME}-temp.dmg"
VOLUME_NAME="${APP_NAME}"

cleanup() {
  if mount | grep -q "/Volumes/${VOLUME_NAME}"; then
    hdiutil detach "/Volumes/${VOLUME_NAME}" -quiet || true
  fi
  rm -rf "$WORK_DIR"
}

trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
mkdir -p "$ICONSET_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

ASSET_DIR="$(cd "$(dirname "$0")/.." && pwd)/IPATool/Assets.xcassets/AppIcon.appiconset"

cp "${ASSET_DIR}/icon_16x16.png" "${ICONSET_DIR}/icon_16x16.png"
cp "${ASSET_DIR}/icon_16x16@2x.png" "${ICONSET_DIR}/icon_16x16@2x.png"
cp "${ASSET_DIR}/icon_32x32.png" "${ICONSET_DIR}/icon_32x32.png"
cp "${ASSET_DIR}/icon_32x32@2x.png" "${ICONSET_DIR}/icon_32x32@2x.png"
cp "${ASSET_DIR}/icon_128x128.png" "${ICONSET_DIR}/icon_128x128.png"
cp "${ASSET_DIR}/icon_128x128@2x.png" "${ICONSET_DIR}/icon_128x128@2x.png"
cp "${ASSET_DIR}/icon_256x256.png" "${ICONSET_DIR}/icon_256x256.png"
cp "${ASSET_DIR}/icon_256x256@2x.png" "${ICONSET_DIR}/icon_256x256@2x.png"
cp "${ASSET_DIR}/icon_512x512.png" "${ICONSET_DIR}/icon_512x512.png"
cp "${ASSET_DIR}/icon_512x512@2x.png" "${ICONSET_DIR}/icon_512x512@2x.png"

iconutil -c icns "${ICONSET_DIR}" -o "${WORK_DIR}/.VolumeIcon.icns"

rm -f "$DMG_PATH"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG_PATH" >/dev/null

MOUNT_OUTPUT="$(hdiutil attach "$RW_DMG_PATH" -readwrite -noautoopen)"
MOUNT_POINT="$(echo "$MOUNT_OUTPUT" | awk '/\/Volumes\// {print substr($0, index($0,$3))}' | tail -n 1)"

if [[ -z "$MOUNT_POINT" ]]; then
  echo "Failed to determine mounted DMG path." >&2
  exit 1
fi

cp "${WORK_DIR}/.VolumeIcon.icns" "${MOUNT_POINT}/.VolumeIcon.icns"
SetFile -a C "${MOUNT_POINT}"
SetFile -a V "${MOUNT_POINT}/.VolumeIcon.icns"
sync

hdiutil detach "$MOUNT_POINT" -quiet

hdiutil convert "$RW_DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
