# VLC Last Seen

A macOS-only VLC Lua interface that applies the Finder tag `last-seen` to the local media file currently opened in VLC.

For each folder, it keeps at most one file tagged `last-seen`. Opening another file from the same folder moves the tag while preserving every unrelated Finder tag and its color.

It also records how far you got in each file as a Finder comment, such as `47%`, so you can tell an interrupted episode from one you stopped during the credits.

## Requirements

- macOS
- VLC installed and launched at least once
- VLC fully closed during installation or uninstallation

## Compatibility

Tested with VLC 3.x on macOS. The Lua source includes a current-item fallback for newer VLC APIs, but VLC 4 compatibility has not yet been verified.

Watch progress is written through Finder scripting, so macOS asks once whether VLC may control Finder. See [Watch progress](#watch-progress).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Carlos-err406/vlc-last-seen/main/install.sh | /bin/bash
```

Then open a local media file normally with VLC by double-clicking it, dragging it into VLC, or using **Open With → VLC**. No menu activation is required.

Rerun the same command to update the installed Lua interface.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/Carlos-err406/vlc-last-seen/main/uninstall.sh | /bin/bash
```

Uninstalling removes the interface and its VLC startup configuration. Existing `last-seen` Finder tags and progress comments are not removed from media files.

## Local installation

```bash
git clone https://github.com/Carlos-err406/vlc-last-seen.git
cd vlc-last-seen
./install.sh
```

To uninstall from a clone:

```bash
./uninstall.sh
```

## How it works

The installer:

1. Copies `src/last-seen.lua` to:

   ```text
   ~/Library/Application Support/org.videolan.vlc/lua/intf/last-seen.lua
   ```

2. Adds this scoped background interface to VLC's `extraintf` chain:

   ```text
   luaintf{intf=last-seen}
   ```

The scoped interface entry allows VLC Last Seen to coexist with other extra interfaces, including other Lua interfaces.

At runtime, the Lua interface watches VLC's current local input. When the input changes, it invokes the macOS-provided `osascript` executable to move the `last-seen` tag while preserving every unrelated tag. While the file plays, it samples the playback position and asks Finder to update the file's progress comment. It does not contact the network at runtime.

## Behavior

Given this folder:

```text
Show/
├── Episode 01.mkv  [favorite, last-seen]
└── Episode 02.mkv  [downloaded]
```

Opening `Episode 02.mkv` in VLC produces:

```text
Show/
├── Episode 01.mkv  [favorite]
└── Episode 02.mkv  [downloaded, last-seen]
```

Only the `last-seen` tag is moved. Other tags are preserved.

Network streams and other non-file VLC inputs are ignored.

## Watch progress

Each file you play gets its watch progress as the first line of its Finder comment:

```text
47%
```

A file at 97% was most likely stopped during the credits; one at 22% was interrupted. Progress is kept per file, so it stays after the `last-seen` tag moves on and you can see which episodes you finished.

To see it in Finder, switch the folder to list view, open **View → Show View Options**, and enable **Comments**. It also appears under **Get Info**.

Only a line consisting of a percentage (such as `47%`) is managed. Any other comment text you wrote is preserved below it.

The comment is updated:

- when you pause
- when you switch to another file or playback ends
- when you quit VLC
- every 30 seconds while playing, if the percentage changed, so a crash or force quit loses at most that much

Positions under 1% never overwrite an existing comment, so opening a file and closing it right away keeps its previous progress.

The first time a comment is written, macOS asks whether VLC may control Finder. If you decline, tagging keeps working and progress comments are turned off. To enable them later, allow VLC to control Finder in **System Settings → Privacy & Security → Automation**, then restart VLC.


## Tag color

VLC Last Seen sets only the tag name. Finder takes the color from its own tag settings. To give `last-seen` a color, right-click it under **Tags** in the Finder sidebar, or in **Finder → Settings → Tags**, and pick one. The color applies to every file with that tag.

## Configuration backups

The installer and uninstaller back up VLC's configuration before changing it. Backups are created next to:

```text
~/Library/Preferences/org.videolan.vlc/vlcrc
```

with names beginning with:

```text
vlcrc.last-seen-backup.
```

## Troubleshooting

Make sure VLC is fully closed with **Cmd+Q**, then reinstall.

To inspect VLC Last Seen logs, launch VLC from Terminal:

```bash
/Applications/VLC.app/Contents/MacOS/VLC -vv
```

Look for messages beginning with:

```text
[last-seen]
```

## License

MIT
