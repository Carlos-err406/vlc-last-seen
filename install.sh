#!/bin/bash

set -euo pipefail

PLUGIN_NAME="last-seen"
INTF_ENTRY="luaintf{intf=${PLUGIN_NAME}}"
RAW_BASE_URL="https://raw.githubusercontent.com/Carlos-err406/vlc-last-seen/main"

VLC_SUPPORT_DIR="${HOME}/Library/Application Support/org.videolan.vlc"
VLC_INTF_DIR="${VLC_SUPPORT_DIR}/lua/intf"
VLC_CONFIG="${HOME}/Library/Preferences/org.videolan.vlc/vlcrc"
TARGET_FILE="${VLC_INTF_DIR}/${PLUGIN_NAME}.lua"

TEMP_SOURCE=""
TEMP_CONFIG=""

cleanup() {
    if [ -n "${TEMP_SOURCE}" ] && [ -f "${TEMP_SOURCE}" ]; then
        rm -f "${TEMP_SOURCE}"
    fi

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

# Remove one module from a colon-separated VLC interface chain while respecting
# colons inside module configuration braces.
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
    fail "VLC is running. Quit it completely with Cmd+Q, then run the installer again."
fi

[ -f "${VLC_CONFIG}" ] || fail "VLC configuration was not found at ${VLC_CONFIG}. Launch VLC once, quit it, and rerun the installer."

SOURCE_FILE=""
SCRIPT_PATH="${BASH_SOURCE[0]:-}"

if [ -n "${SCRIPT_PATH}" ] && [ -f "${SCRIPT_PATH}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
    LOCAL_SOURCE="${SCRIPT_DIR}/src/${PLUGIN_NAME}.lua"

    if [ -f "${LOCAL_SOURCE}" ]; then
        SOURCE_FILE="${LOCAL_SOURCE}"
    fi
fi

if [ -z "${SOURCE_FILE}" ]; then
    command -v curl >/dev/null 2>&1 || fail "curl is required for remote installation."

    TEMP_SOURCE="$(mktemp "${TMPDIR:-/tmp}/vlc-last-seen-source.XXXXXX")"
    echo "Downloading ${PLUGIN_NAME}.lua..."
    curl -fsSL "${RAW_BASE_URL}/src/${PLUGIN_NAME}.lua" -o "${TEMP_SOURCE}"
    SOURCE_FILE="${TEMP_SOURCE}"
fi

[ -s "${SOURCE_FILE}" ] || fail "The Lua interface source is missing or empty."

ACTIVE_EXTRAINTF_COUNT="$(grep -c '^extraintf=' "${VLC_CONFIG}" || true)"

if [ "${ACTIVE_EXTRAINTF_COUNT}" -gt 1 ]; then
    fail "vlcrc contains multiple active extraintf lines. Keep a single extraintf line, then rerun the installer."
fi

CURRENT_EXTRAINTF=""

if [ "${ACTIVE_EXTRAINTF_COUNT}" -eq 1 ]; then
    CURRENT_EXTRAINTF="$(grep '^extraintf=' "${VLC_CONFIG}" | head -n 1 | cut -d= -f2-)"
fi

LEGACY_CONFIG=0

if grep -q '^lua-intf=last-seen$' "${VLC_CONFIG}"; then
    LEGACY_CONFIG=1
fi

# Deduplicate our scoped interface entry. During migration from the old setup,
# also remove the bare luaintf instance that depended on lua-intf=last-seen.
NEW_EXTRAINTF="$(remove_chain_entry "${CURRENT_EXTRAINTF}" "${INTF_ENTRY}")"

if [ "${LEGACY_CONFIG}" -eq 1 ]; then
    NEW_EXTRAINTF="$(remove_chain_entry "${NEW_EXTRAINTF}" "luaintf")"
fi

if [ -n "${NEW_EXTRAINTF}" ]; then
    NEW_EXTRAINTF="${NEW_EXTRAINTF}:${INTF_ENTRY}"
else
    NEW_EXTRAINTF="${INTF_ENTRY}"
fi

BACKUP="${VLC_CONFIG}.last-seen-backup.$(date +%Y%m%d-%H%M%S).$$"
cp -p "${VLC_CONFIG}" "${BACKUP}"

TEMP_CONFIG="$(mktemp "${VLC_CONFIG}.tmp.XXXXXX")"

NEW_EXTRAINTF="${NEW_EXTRAINTF}" LEGACY_CONFIG="${LEGACY_CONFIG}" HAS_ACTIVE_EXTRAINTF="${ACTIVE_EXTRAINTF_COUNT}" awk '
    BEGIN {
        new_extraintf = ENVIRON["NEW_EXTRAINTF"]
        legacy_config = ENVIRON["LEGACY_CONFIG"]
        has_active_extraintf = ENVIRON["HAS_ACTIVE_EXTRAINTF"]
        extraintf_written = 0
    }

    legacy_config == "1" && $0 == "lua-intf=last-seen" {
        print "#lua-intf=last-seen"
        next
    }

    has_active_extraintf == "1" && /^extraintf=/ && extraintf_written == 0 {
        print "extraintf=" new_extraintf
        extraintf_written = 1
        next
    }

    has_active_extraintf == "0" && /^#extraintf=/ && extraintf_written == 0 {
        print "extraintf=" new_extraintf
        extraintf_written = 1
        next
    }

    {
        print
    }

    END {
        if (extraintf_written == 0) {
            print ""
            print "extraintf=" new_extraintf
        }
    }
' "${VLC_CONFIG}" > "${TEMP_CONFIG}"

chmod "$(stat -f '%Lp' "${VLC_CONFIG}")" "${TEMP_CONFIG}"

mkdir -p "${VLC_INTF_DIR}"
install -m 0644 "${SOURCE_FILE}" "${TARGET_FILE}"
mv "${TEMP_CONFIG}" "${VLC_CONFIG}"
TEMP_CONFIG=""

echo
echo "VLC Last Seen installed successfully."
echo "Lua interface: ${TARGET_FILE}"
echo "Config backup: ${BACKUP}"
echo "VLC setting: $(grep '^extraintf=' "${VLC_CONFIG}" | head -n 1)"
echo
echo "Open a local media file normally with VLC. No manual activation is needed."
