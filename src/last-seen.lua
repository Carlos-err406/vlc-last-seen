local TAG_NAME = "last-seen"
local POLL_INTERVAL_US = 500000
local PROGRESS_INTERVAL_US = 30000000
local EXIT_MARKER = "__VLC_LAST_SEEN_EXIT_CODE__"

local TAG_APPLESCRIPT = [[
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

local COMMENT_APPLESCRIPT = [[
on isProgressLine(commentLine)
    -- Earlier versions wrote "last-seen: 47% (22:10 / 47:00)".
    if commentLine starts with "last-seen: " then return true

    if commentLine does not end with "%" or (length of commentLine) < 2 then return false

    set digits to text 1 thru -2 of commentLine

    if (length of digits) > 3 then return false

    repeat with digitRef in characters of digits
        if "0123456789" does not contain (digitRef as text) then return false
    end repeat

    return true
end isProgressLine

on run argv
    set filePath to item 1 of argv
    set progressLine to item 2 of argv

    set targetFile to (POSIX file filePath) as alias

    tell application "Finder"
        set existingComment to comment of targetFile
    end tell

    set keptLines to {}

    repeat with commentRef in paragraphs of existingComment
        set commentLine to commentRef as text

        if not isProgressLine(commentLine) then
            if keptLines is not {} or commentLine is not "" then
                set end of keptLines to commentLine
            end if
        end if
    end repeat

    set savedDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to linefeed
    set newComment to ({progressLine} & keptLines) as text
    set AppleScript's text item delimiters to savedDelimiters

    tell application "Finder"
        set comment of targetFile to newComment
    end tell

    return
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

local function get_position()
    if vlc.player and vlc.player.get_position then
        return vlc.player.get_position()
    end

    if vlc.object and vlc.object.input then
        local input = vlc.object.input()

        if input then
            return vlc.var.get(input, "position")
        end
    end

    return nil
end

local function run_osascript(script, args)
    local command = "/usr/bin/osascript -e " .. shell_quote(script)

    for _, arg in ipairs(args) do
        command = command .. " " .. shell_quote(arg)
    end

    command =
        command ..
        " 2>&1; printf '\\n" ..
        EXIT_MARKER ..
        ":%s\\n' \"$?\""

    local pipe = io.popen(command)

    if not pipe then
        vlc.msg.err("[last-seen] failed to launch osascript")
        return false, ""
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

        return false, message
    end

    if exit_code ~= 0 then
        vlc.msg.err(
            "[last-seen] osascript failed with exit code " ..
            tostring(exit_code)
        )

        if message ~= "" then
            vlc.msg.err("[last-seen] osascript output: " .. message)
        end

        return false, message
    end

    if message ~= "" then
        vlc.msg.info("[last-seen] osascript output: " .. message)
    end

    return true, message
end

local function update_last_seen(path)
    vlc.msg.info("[last-seen] tagging: " .. path)

    if run_osascript(TAG_APPLESCRIPT, { path, TAG_NAME }) then
        vlc.msg.info("[last-seen] tagged successfully")
    end
end

local function progress_line(position)
    local percent = math.floor(position * 100)

    if percent <= 0 then
        return nil
    end

    return percent .. "%"
end

local comments_enabled = true

local function write_progress(progress)
    if not comments_enabled or not progress.line or progress.line == progress.written then
        return
    end

    progress.written = progress.line
    progress.written_at = vlc.misc.mdate()

    vlc.msg.dbg("[last-seen] progress: " .. progress.path .. " " .. progress.line)

    local ok, message = run_osascript(
        COMMENT_APPLESCRIPT,
        { progress.path, progress.line }
    )

    -- -1743: the user denied VLC permission to control Finder.
    if not ok and message:find("-1743", 1, true) then
        comments_enabled = false
        vlc.msg.err(
            "[last-seen] progress comments disabled: allow VLC to control " ..
            "Finder in System Settings > Privacy & Security > Automation, " ..
            "then restart VLC"
        )
    end
end

local function sample_progress(progress)
    local position = get_position()

    if not position then
        return
    end

    -- An unchanged position between polls means playback is paused.
    local paused = position == progress.position
    progress.position = position

    -- Positions under 1% (just opened, stopped, or still at a resume prompt)
    -- keep the last known progress instead of overwriting it.
    local line = progress_line(position)

    if not line then
        return
    end

    progress.line = line

    if paused or vlc.misc.mdate() - progress.written_at >= PROGRESS_INTERVAL_US then
        write_progress(progress)
    end
end

vlc.msg.info("[last-seen] interface started")

local last_uri = nil
local progress = nil

local function finish_progress()
    if progress then
        write_progress(progress)
        progress = nil
    end
end

while true do
    local item = get_current_item()

    if item then
        local uri = item:uri()

        if uri and uri ~= last_uri then
            finish_progress()
            last_uri = uri
            vlc.msg.info("[last-seen] new input: " .. uri)

            local path = uri_to_path(uri)

            if path then
                update_last_seen(path)
                progress = { path = path, written_at = vlc.misc.mdate() }
            end
        end

        if progress then
            sample_progress(progress)
        end
    else
        finish_progress()
        last_uri = nil
    end

    -- VLC interrupts mwait when it quits; save the latest progress first.
    if not pcall(vlc.misc.mwait, vlc.misc.mdate() + POLL_INTERVAL_US) then
        vlc.msg.info("[last-seen] VLC is quitting")
        finish_progress()
        break
    end
end
