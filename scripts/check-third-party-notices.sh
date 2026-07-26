#!/bin/zsh

set -euo pipefail

OPENPANE_SCRIPT_DIR="${0:A:h}"
OPENPANE_PROJECT_DIR="${OPENPANE_SCRIPT_DIR:h}"
OPENPANE_PACKAGE_FILE="${OPENPANE_PROJECT_DIR}/Package.swift"
OPENPANE_RESOLVED_FILE="${OPENPANE_PROJECT_DIR}/Package.resolved"
OPENPANE_NOTICES_FILE="${OPENPANE_PROJECT_DIR}/THIRD_PARTY_NOTICES.md"

if [[ ! -f "${OPENPANE_NOTICES_FILE}" ]]; then
    echo "THIRD_PARTY_NOTICES.md is required." >&2
    exit 1
fi

typeset -a OPENPANE_PACKAGE_URLS
OPENPANE_PACKAGE_URLS=(
    "$(
        {
            sed -n \
            's/.*"\(https:\/\/github\.com\/[^"]*\.git\)".*/\1/p' \
            "${OPENPANE_PACKAGE_FILE}"
            if [[ -f "${OPENPANE_RESOLVED_FILE}" ]]; then
                sed -n \
                    's/.*"location" : "\(https:\/\/github\.com\/[^"]*\)".*/\1/p' \
                    "${OPENPANE_RESOLVED_FILE}"
            fi
        } | sort -u
    )"
)

typeset OPENPANE_PACKAGE_URL
for OPENPANE_PACKAGE_URL in ${=OPENPANE_PACKAGE_URLS}; do
    OPENPANE_PACKAGE_SLUG="${OPENPANE_PACKAGE_URL#https://github.com/}"
    OPENPANE_PACKAGE_SLUG="${OPENPANE_PACKAGE_SLUG%.git}"
    if ! grep -Fq "${OPENPANE_PACKAGE_SLUG}" "${OPENPANE_NOTICES_FILE}"; then
        echo "Missing third-party notice for ${OPENPANE_PACKAGE_SLUG}." >&2
        exit 1
    fi
done

if ! awk -F'|' '
    /^\| [^-]/ {
        license = $4
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", license)
        if (license != "License" &&
            license !~ /^(MIT|Apache-2.0|BSD-3-Clause|BSD-2-Clause and MIT components)$/) {
            print "Unapproved or missing license metadata: " $0 > "/dev/stderr"
            invalid = 1
        }
    }
    END { exit invalid }
' "${OPENPANE_NOTICES_FILE}"; then
    exit 1
fi

echo "Third-party notices cover every declared remote package."
