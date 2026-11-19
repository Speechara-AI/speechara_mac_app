#!/bin/sh
set -eu

if [ "${CONFIGURATION:-}" != "Debug" ]; then
  exit 0
fi

if [ "${SPEECHARA_INSTALL_LOCAL_APP:-0}" != "1" ]; then
  echo "Skipping local app install. Set SPEECHARA_INSTALL_LOCAL_APP=1 to copy Debug builds to ~/Applications."
  exit 0
fi

if [ -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  echo "Skipping local app install because no code signing identity is available."
  exit 0
fi

SOURCE_APP="${CODESIGNING_FOLDER_PATH:-${TARGET_BUILD_DIR}/${WRAPPER_NAME}}"
DESTINATION_DIR="${HOME}/Applications"
DESTINATION_APP="${DESTINATION_DIR}/${WRAPPER_NAME}"
STAGING_APP="${DESTINATION_APP}.staging"
ENTITLEMENTS_PATH="${CODE_SIGN_ENTITLEMENTS:-}"

if [ -n "${ENTITLEMENTS_PATH}" ] && [ "${ENTITLEMENTS_PATH#${SRCROOT}/}" = "${ENTITLEMENTS_PATH}" ]; then
  ENTITLEMENTS_PATH="${SRCROOT}/${ENTITLEMENTS_PATH}"
fi

mkdir -p "${DESTINATION_DIR}"
rm -rf "${STAGING_APP}"
ditto "${SOURCE_APP}" "${STAGING_APP}"

if [ "${ENABLE_HARDENED_RUNTIME:-NO}" = "YES" ]; then
  if [ -n "${ENTITLEMENTS_PATH}" ] && [ -f "${ENTITLEMENTS_PATH}" ]; then
    codesign --force --deep --options runtime --entitlements "${ENTITLEMENTS_PATH}" --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "${STAGING_APP}"
  else
    codesign --force --deep --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "${STAGING_APP}"
  fi
else
  if [ -n "${ENTITLEMENTS_PATH}" ] && [ -f "${ENTITLEMENTS_PATH}" ]; then
    codesign --force --deep --entitlements "${ENTITLEMENTS_PATH}" --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "${STAGING_APP}"
  else
    codesign --force --deep --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "${STAGING_APP}"
  fi
fi

rm -rf "${DESTINATION_APP}"
mv "${STAGING_APP}" "${DESTINATION_APP}"

echo "Installed ${WRAPPER_NAME} to ${DESTINATION_APP}"
