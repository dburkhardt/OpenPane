#!/bin/zsh

set -euo pipefail

OPENPANE_SCRIPT_DIR="${0:A:h}"
OPENPANE_PROJECT_DIR="${OPENPANE_SCRIPT_DIR:h}"
OPENPANE_VERSION="${1:?Usage: ./scripts/notarize-release.sh VERSION}"
OPENPANE_BUILD_NUMBER="${OPENPANE_BUILD_NUMBER:-1}"
OPENPANE_SIGNING_IDENTITY="${OPENPANE_SIGNING_IDENTITY:-}"
OPENPANE_SIGNING_KEYCHAIN="${OPENPANE_SIGNING_KEYCHAIN:-}"
OPENPANE_EXPECTED_TEAM_ID="${OPENPANE_EXPECTED_TEAM_ID:-}"
OPENPANE_NOTARY_TIMEOUT="${OPENPANE_NOTARY_TIMEOUT:-2h}"
OPENPANE_NOTARY_PROFILE="${OPENPANE_NOTARY_PROFILE:-}"
OPENPANE_NOTARY_KEY_PATH="${OPENPANE_NOTARY_KEY_PATH:-}"
OPENPANE_NOTARY_KEY_ID="${OPENPANE_NOTARY_KEY_ID:-}"
OPENPANE_NOTARY_ISSUER_ID="${OPENPANE_NOTARY_ISSUER_ID:-}"
OPENPANE_NOTARY_APPLE_ID="${OPENPANE_NOTARY_APPLE_ID:-}"
OPENPANE_NOTARY_TEAM_ID="${OPENPANE_NOTARY_TEAM_ID:-}"
OPENPANE_NOTARY_PASSWORD="${OPENPANE_NOTARY_PASSWORD:-}"
OPENPANE_DIST_DIR="${OPENPANE_PROJECT_DIR}/dist"
OPENPANE_ARCHIVE_NAME="OpenPane-${OPENPANE_VERSION}-macos-arm64.zip"
OPENPANE_ARCHIVE_PATH="${OPENPANE_DIST_DIR}/${OPENPANE_ARCHIVE_NAME}"
OPENPANE_CHECKSUM_PATH="${OPENPANE_DIST_DIR}/SHA256SUMS"
OPENPANE_RESULT_PATH="${OPENPANE_DIST_DIR}/notarization-result.plist"
OPENPANE_LOG_PATH="${OPENPANE_DIST_DIR}/notarization-log.json"
OPENPANE_NOTARY_WORK_DIR="$(
    mktemp -d "${TMPDIR:-/tmp}/openpane-notary.XXXXXX"
)"
OPENPANE_BUILD_DIR="${OPENPANE_NOTARY_WORK_DIR}/build"
OPENPANE_APP_PATH="${OPENPANE_BUILD_DIR}/OpenPane.app"
OPENPANE_SUBMISSION_PATH="${OPENPANE_NOTARY_WORK_DIR}/OpenPane-notarization.zip"
OPENPANE_SUBMISSION_RESULT="${OPENPANE_NOTARY_WORK_DIR}/result.plist"

function openpane_notary_cleanup {
    /bin/rm -rf "${OPENPANE_NOTARY_WORK_DIR}"
}

function openpane_notary_fail {
    echo "$1" >&2
    exit 1
}

trap openpane_notary_cleanup EXIT

if [[ ! "${OPENPANE_VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' ]]; then
    openpane_notary_fail "The release version is not valid: ${OPENPANE_VERSION}"
fi
if [[ -z "${OPENPANE_SIGNING_IDENTITY}" || "${OPENPANE_SIGNING_IDENTITY}" == "-" ]]; then
    openpane_notary_fail "OPENPANE_SIGNING_IDENTITY must be a Developer ID Application identity."
fi
if [[ -z "${OPENPANE_EXPECTED_TEAM_ID}" ]]; then
    openpane_notary_fail "OPENPANE_EXPECTED_TEAM_ID is required."
fi

typeset -a OPENPANE_NOTARY_AUTH_ARGUMENTS
if [[ -n "${OPENPANE_NOTARY_PROFILE}" ]]; then
    OPENPANE_NOTARY_AUTH_ARGUMENTS=(
        --keychain-profile "${OPENPANE_NOTARY_PROFILE}"
    )
elif [[ -n "${OPENPANE_NOTARY_KEY_PATH}" ||
        -n "${OPENPANE_NOTARY_KEY_ID}" ||
        -n "${OPENPANE_NOTARY_ISSUER_ID}" ]]; then
    if [[ -z "${OPENPANE_NOTARY_KEY_PATH}" ||
          -z "${OPENPANE_NOTARY_KEY_ID}" ||
          -z "${OPENPANE_NOTARY_ISSUER_ID}" ]]; then
        openpane_notary_fail "The notary API key path, key ID, and issuer ID must all be set."
    fi
    OPENPANE_NOTARY_AUTH_ARGUMENTS=(
        --key "${OPENPANE_NOTARY_KEY_PATH}"
        --key-id "${OPENPANE_NOTARY_KEY_ID}"
        --issuer "${OPENPANE_NOTARY_ISSUER_ID}"
    )
elif [[ -n "${OPENPANE_NOTARY_APPLE_ID}" ||
        -n "${OPENPANE_NOTARY_TEAM_ID}" ||
        -n "${OPENPANE_NOTARY_PASSWORD}" ]]; then
    if [[ -z "${OPENPANE_NOTARY_APPLE_ID}" ||
          -z "${OPENPANE_NOTARY_TEAM_ID}" ||
          -z "${OPENPANE_NOTARY_PASSWORD}" ]]; then
        openpane_notary_fail "The notary Apple ID, team ID, and app-specific password must all be set."
    fi
    if [[ "${OPENPANE_NOTARY_TEAM_ID}" != "${OPENPANE_EXPECTED_TEAM_ID}" ]]; then
        openpane_notary_fail "The signing and notarization team IDs do not match."
    fi
    OPENPANE_NOTARY_AUTH_ARGUMENTS=(
        --apple-id "${OPENPANE_NOTARY_APPLE_ID}"
        --team-id "${OPENPANE_NOTARY_TEAM_ID}"
        --password "${OPENPANE_NOTARY_PASSWORD}"
    )
else
    openpane_notary_fail "Notarization credentials are required."
fi

mkdir -p "${OPENPANE_DIST_DIR}"
/bin/rm -f \
    "${OPENPANE_ARCHIVE_PATH}" \
    "${OPENPANE_CHECKSUM_PATH}" \
    "${OPENPANE_RESULT_PATH}" \
    "${OPENPANE_LOG_PATH}"

OPENPANE_VERSION="${OPENPANE_VERSION}" \
OPENPANE_BUILD_NUMBER="${OPENPANE_BUILD_NUMBER}" \
OPENPANE_SIGNING_IDENTITY="${OPENPANE_SIGNING_IDENTITY}" \
OPENPANE_SIGNING_KEYCHAIN="${OPENPANE_SIGNING_KEYCHAIN}" \
OPENPANE_EXPECTED_TEAM_ID="${OPENPANE_EXPECTED_TEAM_ID}" \
OPENPANE_REQUIRE_DEVELOPER_ID=1 \
    "${OPENPANE_SCRIPT_DIR}/build-app.sh" "${OPENPANE_BUILD_DIR}"

ditto \
    -c \
    -k \
    --noextattr \
    --noqtn \
    --norsrc \
    --keepParent \
    "${OPENPANE_APP_PATH}" \
    "${OPENPANE_SUBMISSION_PATH}"

set +e
xcrun notarytool submit \
    "${OPENPANE_SUBMISSION_PATH}" \
    "${OPENPANE_NOTARY_AUTH_ARGUMENTS[@]}" \
    --wait \
    --timeout "${OPENPANE_NOTARY_TIMEOUT}" \
    --output-format plist > "${OPENPANE_SUBMISSION_RESULT}"
OPENPANE_NOTARY_EXIT_CODE=$?
set -e

if [[ ! -s "${OPENPANE_SUBMISSION_RESULT}" ]]; then
    openpane_notary_fail "Apple notarization did not return a result."
fi

cp "${OPENPANE_SUBMISSION_RESULT}" "${OPENPANE_RESULT_PATH}"

OPENPANE_SUBMISSION_ID="$(
    plutil -extract id raw -o - "${OPENPANE_SUBMISSION_RESULT}" 2>/dev/null || true
)"
OPENPANE_NOTARY_STATUS="$(
    plutil -extract status raw -o - "${OPENPANE_SUBMISSION_RESULT}" 2>/dev/null || true
)"

if [[ -n "${OPENPANE_SUBMISSION_ID}" ]]; then
    xcrun notarytool log \
        "${OPENPANE_NOTARY_AUTH_ARGUMENTS[@]}" \
        "${OPENPANE_SUBMISSION_ID}" \
        "${OPENPANE_LOG_PATH}" || true
fi

if [[ "${OPENPANE_NOTARY_EXIT_CODE}" -ne 0 ||
      "${OPENPANE_NOTARY_STATUS}" != "Accepted" ]]; then
    openpane_notary_fail "Apple notarization was not accepted (status: ${OPENPANE_NOTARY_STATUS:-unknown})."
fi

xcrun stapler staple -v "${OPENPANE_APP_PATH}"
xcrun stapler validate -v "${OPENPANE_APP_PATH}"
codesign --verify --deep --strict --verbose=3 "${OPENPANE_APP_PATH}"
spctl --assess --type execute --verbose=4 "${OPENPANE_APP_PATH}"

ditto \
    -c \
    -k \
    --noextattr \
    --noqtn \
    --norsrc \
    --keepParent \
    "${OPENPANE_APP_PATH}" \
    "${OPENPANE_ARCHIVE_PATH}"

(
    cd "${OPENPANE_DIST_DIR}"
    shasum -a 256 "${OPENPANE_ARCHIVE_NAME}" > "SHA256SUMS"
)

echo "${OPENPANE_ARCHIVE_PATH}"
echo "${OPENPANE_CHECKSUM_PATH}"
echo "${OPENPANE_RESULT_PATH}"
echo "${OPENPANE_LOG_PATH}"
