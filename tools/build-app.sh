#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="local.notification-sweep.app"
APP_NAME="Notification Sweep"
EXECUTABLE_NAME="NotificationSweep"
INSTALL_DIR="${HOME}/Applications"
APP_PATH="${INSTALL_DIR}/${APP_NAME}.app"
OLD_APP_PATH="${INSTALL_DIR}/Notify Cleaner.app"
APP_SOURCES=("${ROOT_DIR}/src/"*.m)
ICON_GENERATOR_SOURCE="${ROOT_DIR}/tools/GenerateAppIcon.m"
TEMP_DIR="$(mktemp -d)"
ICONSET_PATH="${TEMP_DIR}/NotificationSweep.iconset"
ICON_FILE_NAME="NotificationSweep.icns"

cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

render_icon() {
  local output="$1"
  local size="$2"
  "${TEMP_DIR}/render-icon" "${output}" "${size}"
}

mkdir -p "${INSTALL_DIR}"
rm -rf "${OLD_APP_PATH}"
rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"

clang -fobjc-arc -framework AppKit "${ICON_GENERATOR_SOURCE}" -o "${TEMP_DIR}/render-icon"
mkdir -p "${ICONSET_PATH}"

render_icon "${ICONSET_PATH}/icon_16x16.png" 16
render_icon "${ICONSET_PATH}/icon_16x16@2x.png" 32
render_icon "${ICONSET_PATH}/icon_32x32.png" 32
render_icon "${ICONSET_PATH}/icon_32x32@2x.png" 64
render_icon "${ICONSET_PATH}/icon_128x128.png" 128
render_icon "${ICONSET_PATH}/icon_128x128@2x.png" 256
render_icon "${ICONSET_PATH}/icon_256x256.png" 256
render_icon "${ICONSET_PATH}/icon_256x256@2x.png" 512
render_icon "${ICONSET_PATH}/icon_512x512.png" 512
render_icon "${ICONSET_PATH}/icon_512x512@2x.png" 1024

iconutil --convert icns --output "${APP_PATH}/Contents/Resources/${ICON_FILE_NAME}" "${ICONSET_PATH}"
clang -fobjc-arc -framework AppKit -framework ApplicationServices "${APP_SOURCES[@]}" -o "${APP_PATH}/Contents/MacOS/${EXECUTABLE_NAME}"

cat > "${APP_PATH}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>${ICON_FILE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

printf 'APPL????' > "${APP_PATH}/Contents/PkgInfo"

/usr/bin/codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${APP_PATH}"

python3 - <<'PY'
import plistlib
import urllib.parse
from pathlib import Path

home = str(Path.home())
plist_path = Path.home() / "Library/Preferences/com.apple.dock.plist"
targets = {
    f"file://{urllib.parse.quote(home)}/Applications/Notify%20Cleaner.app/",
    f"file://{urllib.parse.quote(home)}/Applications/Notification%20Sweep.app/",
}
new_url = f"file://{urllib.parse.quote(home)}/Applications/Notification%20Sweep.app/"

with plist_path.open("rb") as fh:
    data = plistlib.load(fh)

persistent_apps = data.get("persistent-apps", [])
filtered = []
for item in persistent_apps:
    url = (((item or {}).get("tile-data") or {}).get("file-data") or {}).get("_CFURLString")
    if url not in targets:
        filtered.append(item)

filtered.append({
    "tile-data": {
        "file-data": {
            "_CFURLString": new_url,
            "_CFURLStringType": 15,
        }
    },
    "tile-type": "file-tile",
})

data["persistent-apps"] = filtered
with plist_path.open("wb") as fh:
    plistlib.dump(data, fh)
PY

/usr/bin/killall Dock >/dev/null 2>&1 || true

printf 'Built launcher: %s\n' "${APP_PATH}"
