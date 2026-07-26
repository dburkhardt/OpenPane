#!/bin/zsh

set -euo pipefail

OPENPANE_SCRIPT_DIR="${0:A:h}"
OPENPANE_PROJECT_DIR="${OPENPANE_SCRIPT_DIR:h}"
OPENPANE_CACHE_ROOT="$(
    mktemp -d "${TMPDIR:-/tmp}/openpane-icon-check.XXXXXX"
)"
OPENPANE_ICONSET_PATH="${OPENPANE_CACHE_ROOT}/OpenPane.iconset"

function openpane_icon_check_cleanup {
    /bin/rm -rf "${OPENPANE_CACHE_ROOT}"
}

trap openpane_icon_check_cleanup EXIT

if [[ "$#" -gt 0 ]]; then
    OPENPANE_APP_PATH="$1"
    OPENPANE_PLIST_PATH="${OPENPANE_APP_PATH}/Contents/Info.plist"
    OPENPANE_ICON_PATH="${OPENPANE_APP_PATH}/Contents/Resources/OpenPane.icns"
else
    OPENPANE_MASTER_PATH="${OPENPANE_PROJECT_DIR}/Packaging/AppIcon.png"
    OPENPANE_PLIST_PATH="${OPENPANE_PROJECT_DIR}/Packaging/Info.plist"
    OPENPANE_ICON_PATH="${OPENPANE_PROJECT_DIR}/Packaging/OpenPane.icns"

    if [[ ! -s "${OPENPANE_MASTER_PATH}" ]]; then
        echo "Missing app-icon master: ${OPENPANE_MASTER_PATH}" >&2
        exit 1
    fi

    OPENPANE_MASTER_WIDTH="$(
        sips -g pixelWidth "${OPENPANE_MASTER_PATH}" |
            awk '/pixelWidth/ { print $2 }'
    )"
    OPENPANE_MASTER_HEIGHT="$(
        sips -g pixelHeight "${OPENPANE_MASTER_PATH}" |
            awk '/pixelHeight/ { print $2 }'
    )"
    OPENPANE_MASTER_ALPHA="$(
        sips -g hasAlpha "${OPENPANE_MASTER_PATH}" |
            awk '/hasAlpha/ { print $2 }'
    )"

    if [[ "${OPENPANE_MASTER_WIDTH}" != "1024"
        || "${OPENPANE_MASTER_HEIGHT}" != "1024"
        || "${OPENPANE_MASTER_ALPHA}" != "yes" ]]; then
        echo "AppIcon.png must be a 1024 x 1024 PNG with alpha." >&2
        exit 1
    fi
fi

if [[ ! -f "${OPENPANE_PLIST_PATH}" ]]; then
    echo "Missing Info.plist: ${OPENPANE_PLIST_PATH}" >&2
    exit 1
fi

OPENPANE_ICON_FILE="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleIconFile' \
        "${OPENPANE_PLIST_PATH}"
)"
if [[ "${OPENPANE_ICON_FILE}" != "OpenPane.icns" ]]; then
    echo "CFBundleIconFile must be OpenPane.icns." >&2
    exit 1
fi

if [[ ! -s "${OPENPANE_ICON_PATH}" ]]; then
    echo "Missing app icon: ${OPENPANE_ICON_PATH}" >&2
    exit 1
fi

iconutil \
    --convert iconset \
    --output "${OPENPANE_ICONSET_PATH}" \
    "${OPENPANE_ICON_PATH}"

typeset -A OPENPANE_EXPECTED_SIZES
OPENPANE_EXPECTED_SIZES=(
    icon_16x16.png 16
    icon_16x16@2x.png 32
    icon_32x32.png 32
    icon_32x32@2x.png 64
    icon_128x128.png 128
    icon_128x128@2x.png 256
    icon_256x256.png 256
    icon_256x256@2x.png 512
    icon_512x512.png 512
    icon_512x512@2x.png 1024
)

for OPENPANE_ICON_NAME OPENPANE_EXPECTED_SIZE \
    in "${(@kv)OPENPANE_EXPECTED_SIZES}"; do
    OPENPANE_EXTRACTED_ICON="${OPENPANE_ICONSET_PATH}/${OPENPANE_ICON_NAME}"
    if [[ ! -s "${OPENPANE_EXTRACTED_ICON}" ]]; then
        echo "Missing icon representation: ${OPENPANE_ICON_NAME}" >&2
        exit 1
    fi
    OPENPANE_ACTUAL_SIZE="$(
        sips -g pixelWidth "${OPENPANE_EXTRACTED_ICON}" |
            awk '/pixelWidth/ { print $2 }'
    )"
    if [[ "${OPENPANE_ACTUAL_SIZE}" != "${OPENPANE_EXPECTED_SIZE}" ]]; then
        echo "${OPENPANE_ICON_NAME} has the wrong dimensions." >&2
        exit 1
    fi
done

echo "OpenPane app icon is complete."
