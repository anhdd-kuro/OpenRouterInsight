#!/usr/bin/env bash

set -euo pipefail

APP_NAME="Open-router Insight"
SCHEME="OpenRouterCreditMenuBar"
CONFIGURATION="Release"
BUILD_DIR="./build"
APP_PATH="${BUILD_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
INSTALL_DIR="/Applications"

usage() {
  cat <<EOF
Usage: ./scripts/build.sh [--install]

Options:
  --install   Build app and install to /Applications
  -h, --help  Show this help message
EOF
}

INSTALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

echo "Building ${APP_NAME} (${CONFIGURATION})..."

xcodebuild \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${BUILD_DIR}" \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Build output not found at: ${APP_PATH}"
  exit 1
fi

echo "Build completed: ${APP_PATH}"

if [[ "${INSTALL}" == true ]]; then
  TARGET_APP_PATH="${INSTALL_DIR}/${APP_NAME}.app"

  echo "Installing to ${TARGET_APP_PATH}..."

  if [[ -d "${TARGET_APP_PATH}" ]]; then
    rm -rf "${TARGET_APP_PATH}"
  fi

  cp -R "${APP_PATH}" "${TARGET_APP_PATH}"
  echo "Installed successfully to ${TARGET_APP_PATH}"
fi
