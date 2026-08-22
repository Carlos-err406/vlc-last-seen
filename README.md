# VLC Last Seen

A macOS-only VLC Lua interface that applies the Finder tag `last-seen` to the local media file currently opened in VLC.

For each folder, it keeps at most one file tagged `last-seen`. Opening another file from the same folder moves the tag while preserving every unrelated Finder tag and its color. The `last-seen` tag is blue by default, so Finder renders a visible colored dot next to the file.

## Requirements

- macOS
- VLC installed and launched at least once
- VLC fully closed during installation or uninstallation

## Compatibility

Tested with VLC 3.x on macOS. The Lua source includes a current-item fallback for newer VLC APIs, but VLC 4 compatibility has not yet been verified.

Colored custom tags require writing Finder's tag metadata representation directly because Foundation exposes tag names but not a writable per-tag color. That representation is macOS-specific and may require adjustment in a future macOS release.

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

Uninstalling removes the interface and its VLC startup configuration. Existing `last-seen` Finder tags are not removed from media files.

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

At runtime, the Lua interface watches VLC's current local input. When the input changes, it invokes the macOS-provided `osascript` executable, reads Finder's raw tag metadata, and writes the `last-seen` tag with a color index while preserving every unrelated tag and color. It does not contact the network at runtime.

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


## Tag color

`last-seen` is blue by default. To use another Finder color, edit `TAG_COLOR` near the top of `src/last-seen.lua` before installing:

```lua
local TAG_COLOR = 4
```

Finder's colored tag indexes are:

| Value | Color |
|---:|---|
| `1` | Gray |
| `2` | Green |
| `3` | Purple |
| `4` | Blue |
| `5` | Yellow |
| `6` | Red |
| `7` | Orange |

After changing it, rerun the installer to update the installed interface.

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
