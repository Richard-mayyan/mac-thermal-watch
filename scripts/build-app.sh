#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${PROJECT_DIR}/dist/MacThermalWatch.app"

cd "${PROJECT_DIR}"
swift build -c release --product MacThermalWatchApp --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"

mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/MacThermalWatchApp" "${APP_DIR}/Contents/MacOS/MacThermalWatchApp"
cp "${PROJECT_DIR}/AppBundle/Info.plist" "${APP_DIR}/Contents/Info.plist"
codesign --force --deep --sign - "${APP_DIR}"

echo "Application créée : ${APP_DIR}"
echo "Ouvrez-la avec : open \"${APP_DIR}\""
