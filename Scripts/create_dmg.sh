#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-${REPO_ROOT}/Speechara.xcodeproj}"
SCHEME="${SCHEME:-Speechara}"
CONFIGURATION="${CONFIGURATION:-Release}"
PRODUCT_NAME="${PRODUCT_NAME:-Speechara}"
VOLUME_NAME="${VOLUME_NAME:-${PRODUCT_NAME}}"
DMG_NAME="${DMG_NAME:-${PRODUCT_NAME}}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/build/dmg}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${OUTPUT_DIR}/DerivedData}"

APP_PATH="${APP_PATH:-}"
CUSTOM_BACKGROUND_PATH=""
SKIP_BUILD=0
USE_LAYOUT=1
USE_BACKGROUND=1
BUILD_UNSIGNED=0
REVEAL_OUTPUT=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Build a standard drag-to-install DMG for ${PRODUCT_NAME}.

Options:
  --app PATH         Package an existing .app bundle instead of building one.
  --skip-build       Require --app and skip the xcodebuild step.
  --unsigned         Build the app without code signing.
  --output-dir PATH  Write the DMG and temporary files to PATH.
  --volume-name NAME Set the mounted volume name shown in Finder.
  --dmg-name NAME    Set the output filename without the .dmg suffix.
  --background PATH  Use a custom PNG/JPG/TIFF background image.
  --no-background    Skip the background image entirely.
  --no-layout        Skip Finder layout customization. Useful in headless CI.
  --reveal           Reveal the finished DMG in Finder without opening it.
  -h, --help         Show this help message.
EOF
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

reveal_in_finder() {
  local target_path="$1"

  if /usr/bin/osascript - "${target_path}" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set targetFile to POSIX file (item 1 of argv) as alias
  tell application "Finder"
    reveal targetFile
    activate
  end tell
end run
APPLESCRIPT
  then
    return 0
  fi

  open -R "${target_path}" >/dev/null 2>&1 || true
}

require_value() {
  if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
    fail "Missing value for ${1}"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --app)
      require_value "$@"
      APP_PATH="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --unsigned)
      BUILD_UNSIGNED=1
      shift
      ;;
    --output-dir)
      require_value "$@"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --volume-name)
      require_value "$@"
      VOLUME_NAME="$2"
      shift 2
      ;;
    --dmg-name)
      require_value "$@"
      DMG_NAME="$2"
      shift 2
      ;;
    --background)
      require_value "$@"
      CUSTOM_BACKGROUND_PATH="$2"
      shift 2
      ;;
    --no-background)
      USE_BACKGROUND=0
      shift
      ;;
    --no-layout)
      USE_LAYOUT=0
      shift
      ;;
    --reveal)
      REVEAL_OUTPUT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

if [ "${SKIP_BUILD}" -eq 1 ] && [ -z "${APP_PATH}" ]; then
  fail "--skip-build requires --app PATH"
fi

if [ -n "${CUSTOM_BACKGROUND_PATH}" ] && [ ! -f "${CUSTOM_BACKGROUND_PATH}" ]; then
  fail "Background image not found at ${CUSTOM_BACKGROUND_PATH}"
fi

FINAL_DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}.dmg"
TEMP_DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}-rw.dmg"
STAGING_DIR="${OUTPUT_DIR}/staging"
MOUNT_ROOT="${OUTPUT_DIR}/mount"
BACKGROUND_DIR="${STAGING_DIR}/.background"
MOUNT_PATH="${MOUNT_ROOT}/${VOLUME_NAME}"
SWIFT_CACHE_ROOT="${OUTPUT_DIR}/swift-cache"
DEVICE=""

cleanup() {
  local exit_code="$?"

  if [ -n "${DEVICE}" ]; then
    hdiutil detach "${DEVICE}" -quiet >/dev/null 2>&1 || hdiutil detach "${DEVICE}" -force -quiet >/dev/null 2>&1 || true
  fi

  rm -rf "${STAGING_DIR}" "${MOUNT_ROOT}"
  rm -f "${TEMP_DMG_PATH}"

  return "${exit_code}"
}

trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}"
rm -f "${FINAL_DMG_PATH}"

if [ -z "${APP_PATH}" ]; then
  mkdir -p "${DERIVED_DATA_PATH}"
  XCODEBUILD_ARGS=(
    -project "${PROJECT_PATH}"
    -scheme "${SCHEME}"
    -configuration "${CONFIGURATION}"
    -derivedDataPath "${DERIVED_DATA_PATH}"
  )

  if [ "${BUILD_UNSIGNED}" -eq 1 ]; then
    XCODEBUILD_ARGS+=(CODE_SIGNING_ALLOWED=NO)
  fi

  XCODEBUILD_ARGS+=(build)
  xcodebuild "${XCODEBUILD_ARGS[@]}"
  APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${PRODUCT_NAME}.app"
fi

if [ ! -d "${APP_PATH}" ]; then
  fail "App bundle not found at ${APP_PATH}"
fi

APP_BUNDLE_NAME="$(basename "${APP_PATH}")"

if [ "${APP_BUNDLE_NAME##*.}" != "app" ]; then
  fail "Expected an .app bundle, got ${APP_BUNDLE_NAME}"
fi

APP_SIZE_KB="$(du -sk "${APP_PATH}" | awk '{print $1}')"
DMG_SIZE_MB="$(((APP_SIZE_KB + 1023) / 1024 + 80))"

if [ "${DMG_SIZE_MB}" -lt 180 ]; then
  DMG_SIZE_MB=180
fi

rm -rf "${STAGING_DIR}" "${MOUNT_ROOT}"
mkdir -p "${STAGING_DIR}"
ditto "${APP_PATH}" "${STAGING_DIR}/${APP_BUNDLE_NAME}"
ln -s /Applications "${STAGING_DIR}/Applications"

BACKGROUND_FILE_NAME=""

if [ "${USE_BACKGROUND}" -eq 1 ]; then
  mkdir -p "${BACKGROUND_DIR}"

  if [ -n "${CUSTOM_BACKGROUND_PATH}" ]; then
    BACKGROUND_FILE_NAME="$(basename "${CUSTOM_BACKGROUND_PATH}")"
    ditto "${CUSTOM_BACKGROUND_PATH}" "${BACKGROUND_DIR}/${BACKGROUND_FILE_NAME}"
  else
    BACKGROUND_FILE_NAME="dmg-background.png"
    mkdir -p "${SWIFT_CACHE_ROOT}/ModuleCache" "${SWIFT_CACHE_ROOT}/clang"
    SWIFT_MODULECACHE_PATH="${SWIFT_CACHE_ROOT}/ModuleCache" \
      CLANG_MODULE_CACHE_PATH="${SWIFT_CACHE_ROOT}/clang" \
      swift "${SCRIPT_DIR}/generate_dmg_background.swift" "${BACKGROUND_DIR}/${BACKGROUND_FILE_NAME}" "${PRODUCT_NAME}"
  fi
fi

chflags hidden "${STAGING_DIR}/.background" >/dev/null 2>&1 || true

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -fs HFS+ \
  -format UDRW \
  -size "${DMG_SIZE_MB}m" \
  "${TEMP_DMG_PATH}" >/dev/null

mkdir -p "${MOUNT_ROOT}"

ATTACH_OUTPUT="$(
  hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "${MOUNT_PATH}" \
    "${TEMP_DMG_PATH}"
)"
DEVICE="$(printf '%s\n' "${ATTACH_OUTPUT}" | awk '/^\/dev\// { print $1; exit }')"

if [ -z "${DEVICE}" ]; then
  fail "Unable to determine attached DMG device"
fi

if [ "${USE_LAYOUT}" -eq 1 ]; then
  if [ -d "${MOUNT_PATH}/.background" ]; then
    chflags hidden "${MOUNT_PATH}/.background" >/dev/null 2>&1 || true
  fi
  if [ -d "${MOUNT_PATH}/.fseventsd" ]; then
    chflags hidden "${MOUNT_PATH}/.fseventsd" >/dev/null 2>&1 || true
  fi
  if [ -d "${MOUNT_PATH}/.Trashes" ]; then
    chflags hidden "${MOUNT_PATH}/.Trashes" >/dev/null 2>&1 || true
  fi

  if [ -n "${BACKGROUND_FILE_NAME}" ]; then
    if ! osascript "${SCRIPT_DIR}/configure_dmg_layout.applescript" "${VOLUME_NAME}" "${APP_BUNDLE_NAME}" ".background:${BACKGROUND_FILE_NAME}"; then
      fail "Finder layout customization failed. Re-run with --no-layout in headless environments."
    fi
  else
    if ! osascript "${SCRIPT_DIR}/configure_dmg_layout.applescript" "${VOLUME_NAME}" "${APP_BUNDLE_NAME}"; then
      fail "Finder layout customization failed. Re-run with --no-layout in headless environments."
    fi
  fi

  if ! bless --folder "${MOUNT_PATH}" --openfolder "${MOUNT_PATH}" >/dev/null 2>&1; then
    echo "Skipping bless --openfolder for ${MOUNT_PATH}" >&2
  fi

  for _ in 1 2 3 4 5; do
    if [ -f "${MOUNT_PATH}/.DS_Store" ]; then
      cp "${MOUNT_PATH}/.DS_Store" "${STAGING_DIR}/.DS_Store"
      break
    fi
    sleep 1
  done
fi

sync
hdiutil detach "${DEVICE}" -quiet >/dev/null
DEVICE=""

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  "${FINAL_DMG_PATH}" >/dev/null

if [ "${REVEAL_OUTPUT}" -eq 1 ]; then
  reveal_in_finder "${FINAL_DMG_PATH}"
fi

echo "Created ${FINAL_DMG_PATH}"
