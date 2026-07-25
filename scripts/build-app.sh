#!/bin/zsh

set -euo pipefail

OPENPANE_SCRIPT_DIR="${0:A:h}"
OPENPANE_PROJECT_DIR="${OPENPANE_SCRIPT_DIR:h}"
OPENPANE_OUTPUT_DIR="${1:-${OPENPANE_PROJECT_DIR}/dist}"
OPENPANE_CONFIGURATION="${OPENPANE_CONFIGURATION:-release}"
OPENPANE_VERSION="${OPENPANE_VERSION:-0.0.1}"
OPENPANE_BUILD_NUMBER="${OPENPANE_BUILD_NUMBER:-1}"
OPENPANE_APP_PATH="${OPENPANE_OUTPUT_DIR}/OpenPane.app"
OPENPANE_CONTENTS_PATH="${OPENPANE_APP_PATH}/Contents"
OPENPANE_CACHE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/openpane-build.XXXXXX")"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "OpenPane currently supports Apple Silicon only." >&2
    exit 1
fi

function openpane_cleanup {
    /bin/rm -rf "${OPENPANE_CACHE_ROOT}"
}

trap openpane_cleanup EXIT

mkdir -p \
    "${OPENPANE_CONTENTS_PATH}/MacOS" \
    "${OPENPANE_CONTENTS_PATH}/Resources"

env \
    CLANG_MODULE_CACHE_PATH="${OPENPANE_CACHE_ROOT}/clang-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="${OPENPANE_CACHE_ROOT}/swiftpm-cache" \
    swift build \
        --package-path "${OPENPANE_PROJECT_DIR}" \
        --configuration "${OPENPANE_CONFIGURATION}" \
        --disable-sandbox

OPENPANE_BINARY_DIR="$(
    env \
        CLANG_MODULE_CACHE_PATH="${OPENPANE_CACHE_ROOT}/clang-cache" \
        SWIFTPM_MODULECACHE_OVERRIDE="${OPENPANE_CACHE_ROOT}/swiftpm-cache" \
        swift build \
            --package-path "${OPENPANE_PROJECT_DIR}" \
            --configuration "${OPENPANE_CONFIGURATION}" \
            --show-bin-path \
            --disable-sandbox
)"

install -m 755 \
    "${OPENPANE_BINARY_DIR}/OpenPane" \
    "${OPENPANE_CONTENTS_PATH}/MacOS/OpenPane"
install -m 644 \
    "${OPENPANE_PROJECT_DIR}/Packaging/Info.plist" \
    "${OPENPANE_CONTENTS_PATH}/Info.plist"

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString ${OPENPANE_VERSION}" \
    "${OPENPANE_CONTENTS_PATH}/Info.plist"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion ${OPENPANE_BUILD_NUMBER}" \
    "${OPENPANE_CONTENTS_PATH}/Info.plist"

plutil -lint "${OPENPANE_CONTENTS_PATH}/Info.plist"
xattr -cr "${OPENPANE_APP_PATH}"
codesign \
    --force \
    --sign - \
    --options runtime \
    --timestamp=none \
    "${OPENPANE_APP_PATH}"
codesign --verify --deep --strict "${OPENPANE_APP_PATH}"

echo "${OPENPANE_APP_PATH}"
