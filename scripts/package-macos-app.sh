#!/usr/bin/env bash
set -euo pipefail

APP_NAME="StatusMenu"
BUNDLE_ID="com.elite.statusmenu"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKAGE_DIR="${ROOT_DIR}/mac/StatusMenu"
SUPPORT_DIR="${PACKAGE_DIR}/Support"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/macos"
VERSION="${1:-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"

mkdir -p "${ARTIFACT_DIR}"

pushd "${PACKAGE_DIR}" >/dev/null
swift build -c release
popd >/dev/null

BINARY_PATH="$(find "${PACKAGE_DIR}/.build" -type f -name "${APP_NAME}" -path '*release*' | head -n 1)"
if [[ -z "${BINARY_PATH}" ]]; then
  echo "Could not find release binary for ${APP_NAME}" >&2
  exit 1
fi

APP_BUNDLE="${ARTIFACT_DIR}/${APP_NAME}.app"
ZIP_PATH="${ARTIFACT_DIR}/${APP_NAME}-${VERSION}.zip"
PLIST_TEMPLATE="${SUPPORT_DIR}/Info.plist.template"

rm -rf "${APP_BUNDLE}" "${ZIP_PATH}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp "${BINARY_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

sed \
  -e "s#@APP_NAME@#${APP_NAME}#g" \
  -e "s#@BUNDLE_ID@#${BUNDLE_ID}#g" \
  -e "s#@VERSION@#${VERSION}#g" \
  -e "s#@BUILD_NUMBER@#${BUILD_NUMBER}#g" \
  "${PLIST_TEMPLATE}" > "${APP_BUNDLE}/Contents/Info.plist"

if [[ -n "${SIGNING_IDENTITY}" ]]; then
  codesign --force --deep --options runtime --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
elif command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true
fi

ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

if [[ -n "${KEYCHAIN_PROFILE}" ]]; then
  xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${KEYCHAIN_PROFILE}" --wait
  xcrun stapler staple "${APP_BUNDLE}"
  rm -f "${ZIP_PATH}"
  ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"
elif [[ "${REQUIRE_NOTARIZATION}" == "1" ]]; then
  echo "REQUIRE_NOTARIZATION=1 but no KEYCHAIN_PROFILE was provided." >&2
  exit 1
fi

echo "Created ${ZIP_PATH}"
