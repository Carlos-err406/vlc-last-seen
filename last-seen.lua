local TAG_NAME = "last-seen"
local POLL_INTERVAL_US = 500000
local EXIT_MARKER = "__VLC_LAST_SEEN_EXIT_CODE__"

local APPLESCRIPT = [[
use framework "Foundation"

on run argv
    set openedPath to item 1 of argv
    set tagName to item 2 of argv

    set NSURL to current application's |NSURL|
    set NSFileManager to current application's NSFileManager
    set NSMutableArray to current application's NSMutableArray

    set tagKey to current application's NSURLTagNamesKey
    set regularFileKey to current application's NSURLIsRegularFileKey

    set openedURL to NSURL's fileURLWithPath:openedPath
    set folderURL to openedURL's URLByDeletingLastPathComponent()
    set fileManager to NSFileManager's defaultManager()

    set fileURLs to fileManager's contentsOfDirectoryAtURL:folderURL ¬
        includingPropertiesForKeys:{regularFileKey, tagKey} ¬
        options:0 ¬
        |error|:(missing value)

    if fileURLs is missing value then
        error "Could not enumerate folder: " & openedPath
    end if

    set fileCount to (fileURLs's |count|()) as integer

    repeat with i from 0 to (fileCount - 1)
        set fileURL to fileURLs's objectAtIndex:i

        set metadata to fileURL's resourceValuesForKeys:{regularFileKey, tagKey} ¬
            |error|:(missing value)

        if metadata is not missing value then
            set isRegular to metadata's objectForKey:regularFileKey

            if isRegular is not missing value and (isRegular as boolean) then
                set existingTags to metadata's objectForKey:tagKey

                if existingTags is missing value then
                    set mutableTags to NSMutableArray's array()
                else
                    set mutableTags to existingTags's mutableCopy()
                end if

                set hasLastSeen to (mutableTags's containsObject:tagName) as boolean
                set isOpenedFile to (fileURL's isEqual:openedURL) as boolean

                if hasLastSeen and not isOpenedFile then
                    mutableTags's removeObject:tagName

                    set success to fileURL's setResourceValue:mutableTags ¬
                        forKey:tagKey ¬
                        |error|:(missing value)

                    if not success then
                        error "Could not remove tag from: " & ((fileURL's |path|()) as text)
                    end if

                else if isOpenedFile and not hasLastSeen then
                    mutableTags's addObject:tagName

                    set success to fileURL's setResourceValue:mutableTags ¬
                        forKey:tagKey ¬
                        |error|:(missing value)

                    if not success then
                        error "Could not tag: " & openedPath
                    end if
                end if
            end if
        end if
    end repeat
end run
]]

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function get_current_item()
    if vlc.player and vlc.player.item then
        return vlc.player.item()
    end

    if vlc.input and vlc.input.item then
        return vlc.input.item()
    end

    return nil
end

local function uri_to_path(uri)
    if not uri or string.sub(uri, 1, 7) ~= "file://" then
        return nil
    end

    if vlc.strings.make_path then
        return vlc.strings.make_path(uri)
    end

    return vlc.strings.decode_uri(string.sub(uri, 8))
end

local function update_last_seen(uri)
    local path = uri_to_path(uri)

    if not path then
        return false
    end

    vlc.msg.info("[last-seen] tagging: " .. path)

    local command =
        "/usr/bin/osascript -e " ..
        shell_quote(APPLESCRIPT) ..
        " " ..
        shell_quote(path) ..
        " " ..
        shell_quote(TAG_NAME) ..
        " 2>&1; printf '\\n" ..
        EXIT_MARKER ..
        ":%s\\n' \"$?\""

    local pipe = io.popen(command)

    if not pipe then
        vlc.msg.err("[last-seen] failed to launch osascript")
        return false
    end

    local output = pipe:read("*a") or ""
    pipe:close()

    local exit_code = tonumber(
        output:match("\n?" .. EXIT_MARKER .. ":(%d+)%s*$")
    )

    local message = trim(
        output:gsub("\n?" .. EXIT_MARKER .. ":%d+%s*$", "")
    )

    if not exit_code then
        vlc.msg.err("[last-seen] could not determine osascript exit status")

        if message ~= "" then
            vlc.msg.err("[last-seen] osascript output: " .. message)
        end

        return false
    end

    if exit_code ~= 0 then
        vlc.msg.err(
            "[last-seen] osascript failed with exit code " ..
            tostring(exit_code)
        )

        if message ~= "" then
            vlc.msg.err("[last-seen] osascript output: " .. message)
        end

        return false
    end

    if message ~= "" then
        vlc.msg.info("[last-seen] osascript output: " .. message)
    end

    vlc.msg.info("[last-seen] tagged successfully")
    return true
end

vlc.msg.info("[last-seen] interface started")

local last_uri = nil

while true do
    local item = get_current_item()

    if item then
        local uri = item:uri()

        if uri and uri ~= last_uri then
            last_uri = uri
            vlc.msg.info("[last-seen] new input: " .. uri)
            update_last_seen(uri)
        end
    else
        last_uri = nil
    end

    vlc.misc.mwait(vlc.misc.mdate() + POLL_INTERVAL_US)
end
