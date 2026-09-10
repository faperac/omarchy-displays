# Changelog

## 0.1.0

First release.

- Bar widget (`󰍹`) that opens a drag-to-arrange monitor layout panel.
- Resolution, refresh rate, scale, orientation, enable/disable, set-as-primary.
- Monitors are kept edge-to-edge — no gaps the cursor can't cross.
- Apply writes `~/.config/hypr/monitors.lua` (timestamped backup) and reloads
  Hyprland, with a 12-second auto-revert.
- Bundled `omarchy-displays` CLI: standalone window, `--print`, `--nwg`,
  `--from-native`.
