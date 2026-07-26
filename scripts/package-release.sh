#!/bin/zsh

set -euo pipefail

OPENPANE_SCRIPT_DIR="${0:A:h}"
OPENPANE_PROJECT_DIR="${OPENPANE_SCRIPT_DIR:h}"
OPENPANE_VERSION="${1:-0.1.0}"
OPENPANE_BUILD_NUMBER="${OPENPANE_BUILD_NUMBER:-1}"
OPENPANE_DIST_DIR="${OPENPANE_PROJECT_DIR}/dist"
OPENPANE_ARCHIVE_NAME="OpenPane-${OPENPANE_VERSION}-macos-arm64.zip"
OPENPANE_ARCHIVE_PATH="${OPENPANE_DIST_DIR}/${OPENPANE_ARCHIVE_NAME}"
OPENPANE_CHECKSUM_PATH="${OPENPANE_DIST_DIR}/SHA256SUMS"
OPENPANE_VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openpane-package-verify.XXXXXX")"

function openpane_package_cleanup {
    /bin/rm -rf "${OPENPANE_VERIFY_DIR}"
}

trap openpane_package_cleanup EXIT

OPENPANE_VERSION="${OPENPANE_VERSION}" \
OPENPANE_BUILD_NUMBER="${OPENPANE_BUILD_NUMBER}" \
    "${OPENPANE_SCRIPT_DIR}/build-app.sh" "${OPENPANE_DIST_DIR}"

/bin/rm -f "${OPENPANE_ARCHIVE_PATH}" "${OPENPANE_CHECKSUM_PATH}"

ditto \
    -c \
    -k \
    --noextattr \
    --noqtn \
    --norsrc \
    --keepParent \
    "${OPENPANE_DIST_DIR}/OpenPane.app" \
    "${OPENPANE_ARCHIVE_PATH}"

ditto -x -k "${OPENPANE_ARCHIVE_PATH}" "${OPENPANE_VERIFY_DIR}"
codesign \
    --verify \
    --deep \
    --strict \
    --verbose=2 \
    "${OPENPANE_VERIFY_DIR}/OpenPane.app"

(
    cd "${OPENPANE_DIST_DIR}"
    shasum -a 256 "${OPENPANE_ARCHIVE_NAME}" > "SHA256SUMS"
)

echo "${OPENPANE_ARCHIVE_PATH}"
echo "${OPENPANE_CHECKSUM_PATH}"
