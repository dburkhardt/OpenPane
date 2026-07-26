#!/bin/zsh

set -euo pipefail

OPENPANE_SCRIPT_DIR="${0:A:h}"
OPENPANE_PROJECT_DIR="${OPENPANE_SCRIPT_DIR:h}"
OPENPANE_SOURCE_PATH="${1:-${OPENPANE_PROJECT_DIR}/Packaging/AppIcon.png}"
OPENPANE_OUTPUT_PATH="${2:-${OPENPANE_PROJECT_DIR}/Packaging/OpenPane.icns}"
OPENPANE_CACHE_ROOT="$(
    mktemp -d "${TMPDIR:-/tmp}/openpane-icon.XXXXXX"
)"
OPENPANE_ICONSET_PATH="${OPENPANE_CACHE_ROOT}/OpenPane.iconset"

function openpane_icon_cleanup {
    /bin/rm -rf "${OPENPANE_CACHE_ROOT}"
}

trap openpane_icon_cleanup EXIT

if [[ ! -f "${OPENPANE_SOURCE_PATH}" ]]; then
    echo "Missing 1024 px app-icon master: ${OPENPANE_SOURCE_PATH}" >&2
    exit 1
fi

OPENPANE_SOURCE_WIDTH="$(
    sips -g pixelWidth "${OPENPANE_SOURCE_PATH}" |
        awk '/pixelWidth/ { print $2 }'
)"
OPENPANE_SOURCE_HEIGHT="$(
    sips -g pixelHeight "${OPENPANE_SOURCE_PATH}" |
        awk '/pixelHeight/ { print $2 }'
)"
OPENPANE_SOURCE_ALPHA="$(
    sips -g hasAlpha "${OPENPANE_SOURCE_PATH}" |
        awk '/hasAlpha/ { print $2 }'
)"

if [[ "${OPENPANE_SOURCE_WIDTH}" != "1024"
    || "${OPENPANE_SOURCE_HEIGHT}" != "1024"
    || "${OPENPANE_SOURCE_ALPHA}" != "yes" ]]; then
    echo "AppIcon.png must be a 1024 x 1024 PNG with alpha." >&2
    exit 1
fi

mkdir -p "${OPENPANE_ICONSET_PATH}"

function openpane_resize_icon {
    local SIZE="$1"
    local NAME="$2"
    sips \
        -z "${SIZE}" "${SIZE}" \
        "${OPENPANE_SOURCE_PATH}" \
        --out "${OPENPANE_ICONSET_PATH}/${NAME}" \
        >/dev/null
}

openpane_resize_icon 16 icon_16x16.png
openpane_resize_icon 32 icon_16x16@2x.png
openpane_resize_icon 32 icon_32x32.png
openpane_resize_icon 64 icon_32x32@2x.png
openpane_resize_icon 128 icon_128x128.png
openpane_resize_icon 256 icon_128x128@2x.png
openpane_resize_icon 256 icon_256x256.png
openpane_resize_icon 512 icon_256x256@2x.png
openpane_resize_icon 512 icon_512x512.png
openpane_resize_icon 1024 icon_512x512@2x.png

mkdir -p "${OPENPANE_OUTPUT_PATH:h}"
iconutil \
    --convert icns \
    --output "${OPENPANE_OUTPUT_PATH}" \
    "${OPENPANE_ICONSET_PATH}"

if [[ ! -s "${OPENPANE_OUTPUT_PATH}" ]]; then
    echo "iconutil did not create ${OPENPANE_OUTPUT_PATH}." >&2
    exit 1
fi

echo "${OPENPANE_OUTPUT_PATH}"
