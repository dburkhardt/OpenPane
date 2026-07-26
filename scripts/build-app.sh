#!/bin/zsh

set -euo pipefail

OPENPANE_SCRIPT_DIR="${0:A:h}"
OPENPANE_PROJECT_DIR="${OPENPANE_SCRIPT_DIR:h}"
OPENPANE_OUTPUT_DIR="${1:-${OPENPANE_PROJECT_DIR}/dist}"
OPENPANE_CONFIGURATION="${OPENPANE_CONFIGURATION:-release}"
OPENPANE_VERSION="${OPENPANE_VERSION:-0.1.1}"
OPENPANE_BUILD_NUMBER="${OPENPANE_BUILD_NUMBER:-1}"
OPENPANE_SIGNING_IDENTITY="${OPENPANE_SIGNING_IDENTITY:--}"
OPENPANE_SIGNING_KEYCHAIN="${OPENPANE_SIGNING_KEYCHAIN:-}"
OPENPANE_EXPECTED_TEAM_ID="${OPENPANE_EXPECTED_TEAM_ID:-}"
OPENPANE_REQUIRE_DEVELOPER_ID="${OPENPANE_REQUIRE_DEVELOPER_ID:-0}"
OPENPANE_ENTITLEMENTS_PATH="${OPENPANE_PROJECT_DIR}/Packaging/OpenPane.entitlements"
OPENPANE_CACHE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/openpane-build.XXXXXX")"
OPENPANE_APP_PATH="${OPENPANE_CACHE_ROOT}/OpenPane.app"
OPENPANE_FINAL_APP_PATH="${OPENPANE_OUTPUT_DIR}/OpenPane.app"
OPENPANE_CONTENTS_PATH="${OPENPANE_APP_PATH}/Contents"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "OpenPane currently supports Apple Silicon only." >&2
    exit 1
fi

"${OPENPANE_SCRIPT_DIR}/check-app-icon.sh"

function openpane_cleanup {
    /bin/rm -rf "${OPENPANE_CACHE_ROOT}"
}

trap openpane_cleanup EXIT

/bin/rm -rf "${OPENPANE_APP_PATH}" "${OPENPANE_FINAL_APP_PATH}"

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
install -m 644 \
    "${OPENPANE_PROJECT_DIR}/THIRD_PARTY_NOTICES.md" \
    "${OPENPANE_CONTENTS_PATH}/Resources/THIRD_PARTY_NOTICES.md"
install -m 644 \
    "${OPENPANE_PROJECT_DIR}/Packaging/OpenPane.icns" \
    "${OPENPANE_CONTENTS_PATH}/Resources/OpenPane.icns"

find "${OPENPANE_BINARY_DIR}" \
    -maxdepth 1 \
    -type d \
    -name '*.bundle' \
    -print0 |
    while IFS= read -r -d '' OPENPANE_RESOURCE_BUNDLE; do
        ditto \
            --noextattr \
            --noqtn \
            --norsrc \
            "${OPENPANE_RESOURCE_BUNDLE}" \
            "${OPENPANE_CONTENTS_PATH}/Resources/${OPENPANE_RESOURCE_BUNDLE:t}"
    done

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString ${OPENPANE_VERSION}" \
    "${OPENPANE_CONTENTS_PATH}/Info.plist"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion ${OPENPANE_BUILD_NUMBER}" \
    "${OPENPANE_CONTENTS_PATH}/Info.plist"

plutil -lint "${OPENPANE_CONTENTS_PATH}/Info.plist"
xattr -cr "${OPENPANE_APP_PATH}"

if [[ "${OPENPANE_REQUIRE_DEVELOPER_ID}" == "1" && "${OPENPANE_SIGNING_IDENTITY}" == "-" ]]; then
    echo "A Developer ID Application identity is required for this build." >&2
    exit 1
fi

typeset -a OPENPANE_CODESIGN_ARGUMENTS
OPENPANE_CODESIGN_ARGUMENTS=(
    --force
    --sign "${OPENPANE_SIGNING_IDENTITY}"
    --options runtime
    --entitlements "${OPENPANE_ENTITLEMENTS_PATH}"
)

if [[ -n "${OPENPANE_SIGNING_KEYCHAIN}" ]]; then
    OPENPANE_CODESIGN_ARGUMENTS+=(--keychain "${OPENPANE_SIGNING_KEYCHAIN}")
fi

if [[ "${OPENPANE_SIGNING_IDENTITY}" == "-" ]]; then
    OPENPANE_CODESIGN_ARGUMENTS+=(--timestamp=none)
else
    if [[ -z "${OPENPANE_EXPECTED_TEAM_ID}" ]]; then
        echo "OPENPANE_EXPECTED_TEAM_ID is required for Developer ID signing." >&2
        exit 1
    fi
    OPENPANE_CODESIGN_ARGUMENTS+=(--timestamp)
fi

codesign "${OPENPANE_CODESIGN_ARGUMENTS[@]}" "${OPENPANE_APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${OPENPANE_APP_PATH}"

if [[ "${OPENPANE_SIGNING_IDENTITY}" != "-" ]]; then
    OPENPANE_SIGNATURE="$(
        codesign --display --verbose=4 "${OPENPANE_APP_PATH}" 2>&1
    )"

    if [[ "${OPENPANE_SIGNATURE}" == *"Signature=adhoc"* ]]; then
        echo "Developer ID signing unexpectedly produced an ad-hoc signature." >&2
        exit 1
    fi
    if [[ "${OPENPANE_SIGNATURE}" != *"Authority=Developer ID Application:"* ]]; then
        echo "The app is not signed by a Developer ID Application certificate." >&2
        exit 1
    fi
    if [[ "${OPENPANE_SIGNATURE}" != *"TeamIdentifier=${OPENPANE_EXPECTED_TEAM_ID}"* ]]; then
        echo "The app signature does not match team ${OPENPANE_EXPECTED_TEAM_ID}." >&2
        exit 1
    fi
    if [[ "${OPENPANE_SIGNATURE}" != *"Timestamp="* ]]; then
        echo "The app signature does not contain a secure timestamp." >&2
        exit 1
    fi
    if [[ "${OPENPANE_SIGNATURE}" != *"(runtime)"* ]]; then
        echo "The app signature does not enable Hardened Runtime." >&2
        exit 1
    fi
fi

mkdir -p "${OPENPANE_OUTPUT_DIR}"
ditto \
    --noextattr \
    --noqtn \
    --norsrc \
    "${OPENPANE_APP_PATH}" \
    "${OPENPANE_FINAL_APP_PATH}"
# File-provider-backed workspace folders may race to attach Finder metadata to
# a newly copied bundle even when ditto excludes source metadata. Remove only
# metadata from this generated app and retry the strict check a few times. The
# release ZIP is independently verified after extraction.
OPENPANE_FINAL_VERIFIED=0
for OPENPANE_VERIFY_ATTEMPT in {1..5}; do
    xattr -cr "${OPENPANE_FINAL_APP_PATH}"
    xattr -dr com.apple.FinderInfo "${OPENPANE_FINAL_APP_PATH}" 2>/dev/null || true
    xattr -dr com.apple.ResourceFork "${OPENPANE_FINAL_APP_PATH}" 2>/dev/null || true
    if codesign \
        --verify \
        --deep \
        --strict \
        --verbose=2 \
        "${OPENPANE_FINAL_APP_PATH}"; then
        OPENPANE_FINAL_VERIFIED=1
        break
    fi
done
if [[ "${OPENPANE_FINAL_VERIFIED}" != "1" ]]; then
    echo "The copied application did not pass strict signature verification." >&2
    exit 1
fi

echo "${OPENPANE_FINAL_APP_PATH}"
