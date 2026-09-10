# omarchy-displays

A macOS-**Displays**-style monitor arranger for [Omarchy](https://omarchy.org/),
as a **bar plugin**: a `󰍹` button in the Omarchy header opens a popup where you
drag screens to lay them out, set resolution / refresh / scale / rotation, Apply
it live, then Save it to `~/.config/hypr/monitors.lua`.

It uses Omarchy's own Quickshell UI kit (`qs.Ui` / `qs.Commons`) — square
corners, 1px borders, the mono font, `Dropdown` / `Toggle` / `Button` — so it
looks like the rest of the desktop and follows every `omarchy theme` change.

## Why it exists

Omarchy has no graphical display arranger — you hand-edit `monitors.lua`:

```lua
hl.monitor({ output = "eDP-1",    mode = "1920x1080@60", position = "0x0",    scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "2560x1440@60", position = "1920x0", scale = 1 })
```

This gives it a UI: a drag-and-snap canvas (screens snap edge-to-edge and never
overlap), a per-display inspector, a live **Apply** with a 12-second "keep
changes?" safety revert, and **Save** which writes a delimited managed block
into `monitors.lua` (timestamped `.bak` first) then `hyprctl reload`.

## Install

```bash
git clone <your-fork-url> omarchy-displays
cd omarchy-displays
./install.sh right          # bar section: left | center | right   (default: right)
```

`install.sh`:

- copies the plugin to `~/.config/omarchy/plugins/faperac.displays/` and bakes
  the chosen section into its `defaultSection`
- runs `omarchy plugin enable faperac.displays <section>`, `omarchy bar move …`,
  and `omarchy restart shell`
- also installs the standalone `omarchy-displays` CLI into `~/.local/bin`

Move it afterwards with:

```bash
omarchy bar move faperac.displays --section center --index 0
```

Requires `quickshell` and `jq` (both ship with Omarchy).

## Using it

Click the `󰍹` bar button. In the popup:

| Action | How |
|---|---|
| Select a display | click its card |
| Move it | drag the card — it snaps to the other screens |
| Resolution / refresh / scale / orientation | inspector dropdowns |
| Enable / disable an output | the **Enabled** toggle |
| Choose the primary (0,0) display | **Set as primary** |
| Test without saving | **Apply** — then **Keep changes** or let it auto-revert |
| Persist to `monitors.lua` | **Save** |
| Undo edits | **Revert** |

IPC (bind a key if you like):

```bash
omarchy-shell faperac.displays toggle
```

## Standalone window / CLI

No bar, or scripting:

```bash
omarchy-displays            # standalone Quickshell window (same UI)
omarchy-displays --print    # print the Lua for the current live layout
omarchy-displays --nwg      # fall back to the nwg-displays GUI
omarchy-displays --from-native SRC   # write monitors.lua from native monitor= lines
```

After Save, `monitors.lua` gets:

```lua
-- >>> omarchy-displays managed block (generated) >>>
hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "1920x0", scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "2560x1440@59.951", position = "0x0", scale = 1 })
-- <<< omarchy-displays managed block <<<
```

Anything outside that block is preserved. Undo a Save:
`cp ~/.config/hypr/monitors.lua.bak.<timestamp> ~/.config/hypr/monitors.lua && hyprctl reload`.

### Notes / limitations

- The stock `monitors.lua` catch-all `hl.monitor({ output = "", … })` is left in
  place; the managed block is appended after it and wins. If an arrangement
  looks ignored, comment that line out (the CLI warns when it sees an active
  one).
- `transform` (rotation) and `mirror` are carried through. `vrr` / `bitdepth`
  are not written in this version.

## Layout

```
manifest.json            Omarchy plugin manifest (kind: bar-widget)
BarWidget.qml            the 󰍹 bar button + popup loader
Panel.qml                the popup UI (qs.Ui / qs.Commons)
logic.js                 shared pure model helpers (parse / snap / serialise)
bin/omarchy-displays     CLI: monitors.lua writer, --print, --nwg, standalone GUI
qml/Displays.qml         standalone-window mirror of the UI (no qs.* deps)
install.sh · share/…
```

## Proposing this to Omarchy

- The plugin is already in first-party shape (`manifest.json` +
  `BarWidget.qml` + `Panel.qml`, `omarchy plugin validate` clean). It could ship
  under `shell/plugins/omarchy.displays/`.
- `bin/omarchy-displays` would become `omarchy monitor arrange` /
  `omarchy-monitor-arrange`; its `--from-native` (native `monitor=` → Lua
  `hl.monitor{}`) is the bit that makes any Hyprland display tool usable on
  Omarchy's Lua config.
- `nwg-displays` stays an optional `--nwg` fallback (lazy `omarchy pkg add`).

## License

MIT — see `LICENSE`.
