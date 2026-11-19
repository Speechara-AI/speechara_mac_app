#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-${REPO_ROOT}/Speechara.xcodeproj}"
SCHEME="${SCHEME:-Speechara}"
CONFIGURATION="${CONFIGURATION:-Release}"
PRODUCT_NAME="${PRODUCT_NAME:-Speechara}"
UPDATE_BASE_URL="${UPDATE_BASE_URL:-https://updates.speechara.ai}"
PLATFORM_NAME="${PLATFORM_NAME:-macOS}"
CHANGELOG_PATH="${CHANGELOG_PATH:-${REPO_ROOT}/CHANGELOG-macOS.md}"

SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.2}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-ai.speechara.mac}"
SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-}"
LOCAL_SPARKLE_ED_KEY_FILE="${LOCAL_SPARKLE_ED_KEY_FILE:-${HOME}/.config/speechara/sparkle_ed_private_key}"

SFTP_KEY="${SFTP_KEY:-/Users/alexdem/.ssh/speechara_updates_deploy_ed25519}"
SFTP_USER="${SFTP_USER:-speechara-updates-deploy}"
SFTP_HOST="${SFTP_HOST:-108.61.87.27}"
PUBLISH_DOWNLOAD_ALIAS="${PUBLISH_DOWNLOAD_ALIAS:-1}"
DOWNLOAD_ALIAS_REMOTE_DIR="${DOWNLOAD_ALIAS_REMOTE_DIR:-/www/download}"
DOWNLOAD_ALIAS_FILE_NAME="${DOWNLOAD_ALIAS_FILE_NAME:-Speechara.dmg}"
DOWNLOAD_METADATA_FILE_NAME="${DOWNLOAD_METADATA_FILE_NAME:-latest.json}"
HISTORY_REMOTE_DIR="${HISTORY_REMOTE_DIR:-/www/history/mac}"
HISTORY_URL="${HISTORY_URL:-${UPDATE_BASE_URL}/history/mac/index.html}"

BUILD_DIR="${BUILD_DIR:-${REPO_ROOT}/build/update}"
DMG_OUTPUT_DIR="${DMG_OUTPUT_DIR:-${BUILD_DIR}/dmg}"
STAGING_DIR="${STAGING_DIR:-${BUILD_DIR}/staging}"
ARCHIVES_DIR="${ARCHIVES_DIR:-${STAGING_DIR}/archives}"

VERSION=""
RELEASE_NOTES_PATH=""
DEPLOY=1
DRY_RUN=0
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-speechara-notary}"
CREATE_DMG_ARGS=()
SKIP_NOTARIZATION_REQUESTED=0
NO_LAYOUT_REQUESTED=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Build, sign, and publish a Sparkle update to ${UPDATE_BASE_URL}.

Options:
  --version VERSION       Release version. Defaults to MARKETING_VERSION.
  --release-notes PATH    HTML, Markdown, or text release notes for this update.
  --changelog PATH        Platform changelog source. Default: CHANGELOG-macOS.md.
  --no-deploy             Generate artifacts locally without uploading by SFTP.
  --dry-run               Print the SFTP batch instead of uploading.
  --notary-profile NAME   notarytool keychain profile for create_dmg.sh.
  --skip-notarization     Pass through to create_dmg.sh for local-only, no-deploy testing.
  --sign-identity ID      Pass through to create_dmg.sh.
  --no-layout             Pass through to create_dmg.sh for local-only, no-deploy testing.
  --layout-metadata PATH  Reuse the verified branded Finder layout from an earlier installer.
  -h, --help              Show this help message.

Environment:
  SPARKLE_KEY_ACCOUNT     Keychain account used by Sparkle tools. Default: ai.speechara.mac.
  SPARKLE_ED_PRIVATE_KEY  CI secret containing exported Sparkle private key.
  SPARKLE_ED_KEY_FILE     Path to exported Sparkle private key file.
  LOCAL_SPARKLE_ED_KEY_FILE
                          Local fallback key file. Default: ~/.config/speechara/sparkle_ed_private_key.
  SFTP_KEY                Deploy key path. Default: /Users/alexdem/.ssh/speechara_updates_deploy_ed25519.
  PUBLISH_DOWNLOAD_ALIAS  Upload stable website download files. Default: 1.
  DOWNLOAD_ALIAS_REMOTE_DIR
                          Remote directory for stable website downloads. Default: /www/download.
  DOWNLOAD_ALIAS_FILE_NAME
                          Stable website DMG file name. Default: Speechara.dmg.
  DOWNLOAD_METADATA_FILE_NAME
                          Stable latest metadata file name. Default: latest.json.
  HISTORY_REMOTE_DIR      Remote history directory. Default: /www/history/mac.
  HISTORY_URL             Public history URL. Default: ${UPDATE_BASE_URL}/history/mac/index.html.
EOF
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required but was not found"
}

has_developer_id_identity() {
  security find-identity -v -p codesigning 2>/dev/null |
    grep -q '"Developer ID Application:'
}

has_notarization_credentials() {
  if [ -n "${NOTARYTOOL_PROFILE}" ]; then
    xcrun notarytool history --keychain-profile "${NOTARYTOOL_PROFILE}" >/dev/null 2>&1
    return $?
  fi

  [ -n "${NOTARY_APPLE_ID:-}" ] &&
    [ -n "${NOTARY_TEAM_ID:-}" ] &&
    [ -n "${NOTARY_PASSWORD:-}" ]
}

read_build_setting() {
  local key="$1"

  xcodebuild \
    -showBuildSettings \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" 2>/dev/null |
    awk -F' = ' -v key="${key}" '
      {
        setting = $1
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", setting)
        if (setting == key) {
          print $2
          exit
        }
      }
    ' || true
}

sparkle_tools_root() {
  if [ -n "${SPARKLE_TOOLS_DIR}" ]; then
    [ -x "${SPARKLE_TOOLS_DIR}/bin/generate_appcast" ] || fail "generate_appcast not found in ${SPARKLE_TOOLS_DIR}/bin"
    printf '%s\n' "${SPARKLE_TOOLS_DIR}"
    return 0
  fi

  local tools_root="${BUILD_DIR}/sparkle-tools/Sparkle-${SPARKLE_VERSION}"
  if [ -x "${tools_root}/bin/generate_appcast" ]; then
    printf '%s\n' "${tools_root}"
    return 0
  fi

  require_command curl
  require_command unzip

  local zip_path="${BUILD_DIR}/sparkle-tools/Sparkle-for-Swift-Package-Manager-${SPARKLE_VERSION}.zip"
  mkdir -p "$(dirname "${zip_path}")" "${tools_root}"

  echo "Downloading Sparkle ${SPARKLE_VERSION} tools" >&2
  curl -fL \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip" \
    -o "${zip_path}"

  rm -rf "${tools_root}"
  mkdir -p "${tools_root}"
  unzip -q "${zip_path}" -d "${tools_root}"
  [ -x "${tools_root}/bin/generate_appcast" ] || fail "Downloaded Sparkle tools are missing generate_appcast"

  printf '%s\n' "${tools_root}"
}

make_default_release_notes() {
  local output_path="$1"

  cat > "${output_path}" <<EOF
<!doctype html>
<html>
<body>
  <h1>${PRODUCT_NAME} ${VERSION}</h1>
  <p>Bug fixes and improvements.</p>
</body>
</html>
EOF
}

make_download_metadata() {
  local output_path="$1"

  cat > "${output_path}" <<EOF
{
  "product": "${PRODUCT_NAME}",
  "version": "${VERSION}",
  "build": "${BUILD_VERSION}",
  "download_url": "${DOWNLOAD_ALIAS_URL}",
  "versioned_download_url": "${UPDATE_BASE_URL}/releases/${DMG_FILE_NAME}",
  "release_notes_url": "${UPDATE_BASE_URL}/release-notes/${RELEASE_NOTES_FILE_NAME}"
}
EOF
}

generate_appcast() {
  local generate_appcast_path="$1"
  local appcast_output_path="$2"

  local args=(
    --download-url-prefix "${UPDATE_BASE_URL}/releases/"
    --release-notes-url-prefix "${UPDATE_BASE_URL}/release-notes/"
    --maximum-versions 0
    -o "${appcast_output_path}"
    "${ARCHIVES_DIR}"
  )

  if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    printf '%s' "${SPARKLE_ED_PRIVATE_KEY}" |
      "${generate_appcast_path}" --ed-key-file - "${args[@]}"
  elif [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
    "${generate_appcast_path}" --ed-key-file "${SPARKLE_ED_KEY_FILE}" "${args[@]}"
  elif [ -f "${LOCAL_SPARKLE_ED_KEY_FILE}" ]; then
    "${generate_appcast_path}" --ed-key-file "${LOCAL_SPARKLE_ED_KEY_FILE}" "${args[@]}"
  else
    "${generate_appcast_path}" --account "${SPARKLE_KEY_ACCOUNT}" "${args[@]}"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      [ $# -ge 2 ] || fail "Missing value for --version"
      VERSION="$2"
      shift 2
      ;;
    --release-notes)
      [ $# -ge 2 ] || fail "Missing value for --release-notes"
      RELEASE_NOTES_PATH="$2"
      shift 2
      ;;
    --changelog)
      [ $# -ge 2 ] || fail "Missing value for --changelog"
      CHANGELOG_PATH="$2"
      shift 2
      ;;
    --no-deploy)
      DEPLOY=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --notary-profile)
      [ $# -ge 2 ] || fail "Missing value for --notary-profile"
      NOTARYTOOL_PROFILE="$2"
      shift 2
      ;;
    --skip-notarization)
      SKIP_NOTARIZATION_REQUESTED=1
      CREATE_DMG_ARGS+=("$1")
      shift
      ;;
    --no-layout)
      NO_LAYOUT_REQUESTED=1
      CREATE_DMG_ARGS+=("$1")
      shift
      ;;
    --layout-metadata)
      [ $# -ge 2 ] || fail "Missing value for --layout-metadata"
      CREATE_DMG_ARGS+=("$1" "$2")
      shift 2
      ;;
    --sign-identity)
      [ $# -ge 2 ] || fail "Missing value for --sign-identity"
      CREATE_DMG_ARGS+=("$1" "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

require_command xcodebuild
require_command curl
require_command python3
if [ "${DEPLOY}" -eq 1 ]; then
  require_command sftp
  require_command security
fi

if [ -z "${VERSION}" ]; then
  VERSION="$(read_build_setting MARKETING_VERSION)"
fi
[ -n "${VERSION}" ] || fail "Could not determine MARKETING_VERSION. Pass --version."
DOWNLOAD_ALIAS_REMOTE_PATH="${DOWNLOAD_ALIAS_REMOTE_DIR}/${DOWNLOAD_ALIAS_FILE_NAME}"
DOWNLOAD_METADATA_REMOTE_PATH="${DOWNLOAD_ALIAS_REMOTE_DIR}/${DOWNLOAD_METADATA_FILE_NAME}"
DOWNLOAD_ALIAS_URL="${UPDATE_BASE_URL}/download/${DOWNLOAD_ALIAS_FILE_NAME}"
HISTORY_FILE_NAME="index.html"
HISTORY_REMOTE_PARENT_DIR="${HISTORY_REMOTE_DIR%/*}"
HISTORY_REMOTE_PATH="${HISTORY_REMOTE_DIR}/${HISTORY_FILE_NAME}"

[ -f "${CHANGELOG_PATH}" ] || fail "Changelog not found: ${CHANGELOG_PATH}"

if [ "${DEPLOY}" -eq 1 ] && [ "${SKIP_NOTARIZATION_REQUESTED}" -eq 1 ]; then
  fail "--skip-notarization cannot be used when deploying updates. Published updates must be Developer ID signed and notarized. Use --no-deploy for local-only test artifacts."
fi

if [ "${DEPLOY}" -eq 1 ] && [ "${NO_LAYOUT_REQUESTED}" -eq 1 ]; then
  fail "--no-layout cannot be used when deploying updates. Published DMGs must keep the branded Finder background and drag-to-Applications layout. Use --no-deploy for local-only headless test artifacts."
fi

if [ "${DEPLOY}" -eq 1 ] && ! has_developer_id_identity; then
  fail "No Developer ID Application signing identity was found in Keychain. Install the Developer ID Application certificate before publishing updates."
fi

if [ "${DEPLOY}" -eq 1 ] && ! has_notarization_credentials; then
  fail "No notarization credentials found. Run 'xcrun notarytool store-credentials ${NOTARYTOOL_PROFILE} ...' or set NOTARY_APPLE_ID, NOTARY_TEAM_ID, and NOTARY_PASSWORD before publishing updates."
fi

BUILD_VERSION="$(read_build_setting CURRENT_PROJECT_VERSION)"

rm -rf "${STAGING_DIR}"
mkdir -p "${DMG_OUTPUT_DIR}" "${ARCHIVES_DIR}"

DMG_FILE_NAME="${PRODUCT_NAME}-${VERSION}.dmg"
DMG_PATH="${DMG_OUTPUT_DIR}/${DMG_FILE_NAME}"

if [ -n "${NOTARYTOOL_PROFILE}" ]; then
  CREATE_DMG_ARGS+=(--notary-profile "${NOTARYTOOL_PROFILE}")
fi

"${SCRIPT_DIR}/create_dmg.sh" \
  --output-dir "${DMG_OUTPUT_DIR}" \
  --dmg-name "${PRODUCT_NAME}-${VERSION}" \
  "${CREATE_DMG_ARGS[@]}"

[ -f "${DMG_PATH}" ] || fail "Expected DMG was not created: ${DMG_PATH}"
cp "${DMG_PATH}" "${ARCHIVES_DIR}/${DMG_FILE_NAME}"

RELEASE_NOTES_FILE_NAME="${PRODUCT_NAME}-${VERSION}.html"
ASSOCIATED_NOTES_PATH="${ARCHIVES_DIR}/${RELEASE_NOTES_FILE_NAME}"
DEPLOY_NOTES_PATH="${STAGING_DIR}/${RELEASE_NOTES_FILE_NAME}"
GENERATED_NOTES_PATH="${STAGING_DIR}/generated-${RELEASE_NOTES_FILE_NAME}"
HISTORY_PATH="${STAGING_DIR}/history/mac/${HISTORY_FILE_NAME}"

python3 "${SCRIPT_DIR}/generate_version_history.py" \
  --changelog "${CHANGELOG_PATH}" \
  --product "${PRODUCT_NAME}" \
  --platform-name "${PLATFORM_NAME}" \
  --version "${VERSION}" \
  --release-notes-output "${GENERATED_NOTES_PATH}" \
  --history-output "${HISTORY_PATH}" \
  --history-url "${HISTORY_URL}"

if [ -n "${RELEASE_NOTES_PATH}" ]; then
  [ -f "${RELEASE_NOTES_PATH}" ] || fail "Release notes file not found: ${RELEASE_NOTES_PATH}"
  cp "${RELEASE_NOTES_PATH}" "${ASSOCIATED_NOTES_PATH}"
else
  cp "${GENERATED_NOTES_PATH}" "${ASSOCIATED_NOTES_PATH}"
fi
cp "${ASSOCIATED_NOTES_PATH}" "${DEPLOY_NOTES_PATH}"

DOWNLOAD_METADATA_PATH="${STAGING_DIR}/${DOWNLOAD_METADATA_FILE_NAME}"
if [ "${PUBLISH_DOWNLOAD_ALIAS}" -eq 1 ]; then
  make_download_metadata "${DOWNLOAD_METADATA_PATH}"
fi

REMOTE_APPCAST_TMP="${STAGING_DIR}/remote-appcast.xml"
if curl -fsSL "${UPDATE_BASE_URL}/appcast.xml" -o "${REMOTE_APPCAST_TMP}" &&
   grep -q '<rss' "${REMOTE_APPCAST_TMP}"; then
  cp "${REMOTE_APPCAST_TMP}" "${ARCHIVES_DIR}/appcast.xml"
fi

TOOLS_ROOT="$(sparkle_tools_root)"
APPCAST_PATH="${STAGING_DIR}/appcast.xml"
generate_appcast "${TOOLS_ROOT}/bin/generate_appcast" "${APPCAST_PATH}"

if [ "${DEPLOY}" -eq 0 ]; then
  echo "Artifacts generated without deploy:"
  echo "  ${DMG_PATH}"
  echo "  ${APPCAST_PATH}"
  echo "  ${DEPLOY_NOTES_PATH}"
  echo "  ${HISTORY_PATH}"
  exit 0
fi

SFTP_BATCH="${STAGING_DIR}/deploy.sftp"
cat > "${SFTP_BATCH}" <<EOF
put ${DMG_PATH} /www/releases/${DMG_FILE_NAME}
put ${DEPLOY_NOTES_PATH} /www/release-notes/${RELEASE_NOTES_FILE_NAME}
-mkdir ${HISTORY_REMOTE_PARENT_DIR}
-mkdir ${HISTORY_REMOTE_DIR}
put ${HISTORY_PATH} ${HISTORY_REMOTE_PATH}
EOF

if [ "${PUBLISH_DOWNLOAD_ALIAS}" -eq 1 ]; then
  cat >> "${SFTP_BATCH}" <<EOF
-mkdir ${DOWNLOAD_ALIAS_REMOTE_DIR}
put ${DMG_PATH} ${DOWNLOAD_ALIAS_REMOTE_PATH}
put ${DOWNLOAD_METADATA_PATH} ${DOWNLOAD_METADATA_REMOTE_PATH}
chmod 0644 ${DOWNLOAD_ALIAS_REMOTE_PATH}
chmod 0644 ${DOWNLOAD_METADATA_REMOTE_PATH}
EOF
fi

cat >> "${SFTP_BATCH}" <<EOF
put ${APPCAST_PATH} /www/appcast.xml
EOF

if [ "${DRY_RUN}" -eq 1 ]; then
  echo "SFTP dry run for ${SFTP_USER}@${SFTP_HOST}:"
  cat "${SFTP_BATCH}"
  exit 0
fi

[ -f "${SFTP_KEY}" ] || fail "SFTP key not found: ${SFTP_KEY}"
sftp -i "${SFTP_KEY}" -b "${SFTP_BATCH}" "${SFTP_USER}@${SFTP_HOST}"

cat <<EOF
Published ${PRODUCT_NAME} ${VERSION}
  ${UPDATE_BASE_URL}/appcast.xml
  ${UPDATE_BASE_URL}/releases/${DMG_FILE_NAME}
  ${UPDATE_BASE_URL}/release-notes/${RELEASE_NOTES_FILE_NAME}
  ${HISTORY_URL}
  ${DOWNLOAD_ALIAS_URL}
  ${UPDATE_BASE_URL}/download/${DOWNLOAD_METADATA_FILE_NAME}

If Cloudflare cached an earlier 404 for this exact DMG URL, purge:
  ${UPDATE_BASE_URL}/releases/${DMG_FILE_NAME}
EOF
