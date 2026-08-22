#!/bin/bash

set -euo pipefail

PLUGIN_NAME="last-seen"
INTF_ENTRY="luaintf{intf=${PLUGIN_NAME}}"

VLC_SUPPORT_DIR="${HOME}/Library/Application Support/org.videolan.vlc"
VLC_INTF_DIR="${VLC_SUPPORT_DIR}/lua/intf"
VLC_CONFIG="${HOME}/Library/Preferences/org.videolan.vlc/vlcrc"
TARGET_FILE="${VLC_INTF_DIR}/${PLUGIN_NAME}.lua"

TEMP_CONFIG=""

cleanup() {
    if [ -n "${TEMP_CONFIG}" ] && [ -f "${TEMP_CONFIG}" ]; then
        rm -f "${TEMP_CONFIG}"
    fi
}

trap cleanup EXIT

fail() {
    echo "Error: $*" >&2
    exit 1
}

vlc_is_running() {
    pgrep -x VLC >/dev/null 2>&1 ||
        pgrep -f '/VLC\.app/Contents/MacOS/VLC' >/dev/null 2>&1
}

remove_chain_entry() {
    local value="$1"
    local target="$2"

    printf '%s\n' "${value}" | awk -v target="${target}" '
        BEGIN {
            depth = 0
            token = ""
            output = ""
        }

        {
            value = $0

            for (i = 1; i <= length(value); i++) {
                char = substr(value, i, 1)

                if (char == "{") {
                    depth++
                } else if (char == "}" && depth > 0) {
                    depth--
                }

                if (char == ":" && depth == 0) {
                    emit(token)
                    token = ""
                } else {
                    token = token char
                }
            }

            emit(token)
        }

        function emit(candidate) {
            if (candidate == "" || candidate == target) {
                return
            }

            if (output != "") {
                output = output ":"
            }

            output = output candidate
        }

        END {
            printf "%s", output
        }
    '
}

if [ "$(uname -s)" != "Darwin" ]; then
    fail "VLC Last Seen currently supports macOS only."
fi

if vlc_is_running; then
    fail "VLC is running. Quit it completely with Cmd+Q, then run the uninstaller again."
fi

CONFIG_CHANGED=0
BACKUP=""
LEGACY_CONFIG=0
CURRENT_EXTRAINTF=""
NEW_EXTRAINTF=""

if [ -f "${VLC_CONFIG}" ]; then
    ACTIVE_EXTRAINTF_COUNT="$(grep -c '^extraintf=' "${VLC_CONFIG}" || true)"

    if [ "${ACTIVE_EXTRAINTF_COUNT}" -gt 1 ]; then
        fail "vlcrc contains multiple active extraintf lines. Keep a single extraintf line, then rerun the uninstaller."
    fi

    if [ "${ACTIVE_EXTRAINTF_COUNT}" -eq 1 ]; then
        CURRENT_EXTRAINTF="$(grep '^extraintf=' "${VLC_CONFIG}" | head -n 1 | cut -d= -f2-)"
    fi

    if grep -q '^lua-intf=last-seen$' "${VLC_CONFIG}"; then
        LEGACY_CONFIG=1
    fi

    NEW_EXTRAINTF="$(remove_chain_entry "${CURRENT_EXTRAINTF}" "${INTF_ENTRY}")"

    if [ "${LEGACY_CONFIG}" -eq 1 ]; then
        NEW_EXTRAINTF="$(remove_chain_entry "${NEW_EXTRAINTF}" "luaintf")"
    fi

    if [ "${NEW_EXTRAINTF}" != "${CURRENT_EXTRAINTF}" ] || [ "${LEGACY_CONFIG}" -eq 1 ]; then
        CONFIG_CHANGED=1
        BACKUP="${VLC_CONFIG}.last-seen-backup.$(date +%Y%m%d-%H%M%S).$$"
        cp -p "${VLC_CONFIG}" "${BACKUP}"

        TEMP_CONFIG="$(mktemp "${VLC_CONFIG}.tmp.XXXXXX")"

        NEW_EXTRAINTF="${NEW_EXTRAINTF}" LEGACY_CONFIG="${LEGACY_CONFIG}" awk '
            BEGIN {
                new_extraintf = ENVIRON["NEW_EXTRAINTF"]
                legacy_config = ENVIRON["LEGACY_CONFIG"]
                extraintf_written = 0
            }

            legacy_config == "1" && $0 == "lua-intf=last-seen" {
                print "#lua-intf=last-seen"
                next
            }

            /^extraintf=/ && extraintf_written == 0 {
                if (new_extraintf == "") {
                    print "#extraintf="
                } else {
                    print "extraintf=" new_extraintf
                }

                extraintf_written = 1
                next
            }

            {
                print
            }
        ' "${VLC_CONFIG}" > "${TEMP_CONFIG}"

        chmod "$(stat -f '%Lp' "${VLC_CONFIG}")" "${TEMP_CONFIG}"
        mv "${TEMP_CONFIG}" "${VLC_CONFIG}"
        TEMP_CONFIG=""
    fi
fi

FILE_REMOVED=0

if [ -f "${TARGET_FILE}" ]; then
    rm -f "${TARGET_FILE}"
    FILE_REMOVED=1
fi

rmdir "${VLC_INTF_DIR}" 2>/dev/null || true
rmdir "${VLC_SUPPORT_DIR}/lua" 2>/dev/null || true

if [ "${CONFIG_CHANGED}" -eq 0 ] && [ "${FILE_REMOVED}" -eq 0 ]; then
    echo "VLC Last Seen is not installed."
    exit 0
fi

echo "VLC Last Seen uninstalled successfully."

if [ -n "${BACKUP}" ]; then
    echo "Config backup: ${BACKUP}"
fi

echo "Existing Finder tags were left unchanged."
