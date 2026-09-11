# Changelog

## Unreleased

- Fixed: Identify flashed every card at once, which defeats the point —
  there was no way to tell which card was which monitor. It now flashes only
  the card for the monitor the real pointer is currently on.
- Removed the `--nwg` fallback and `install.sh` from the plugin. The plugin
  never needed them (the panel writes `monitors.lua` directly via the bundled
  CLI's `--from-native`), and dropping them removes all package-manager /
  privilege / installer surface. Dev setup is now a one-line symlink (see
  README).

## 0.1.0

First release.

- Bar widget (`󰍹`) that opens a drag-to-arrange monitor layout panel.
- Resolution, refresh rate, scale, orientation, enable/disable, set-as-primary.
- Monitors are kept edge-to-edge — no gaps the cursor can't cross.
- Apply writes `~/.config/hypr/monitors.lua` (timestamped backup) and reloads
  Hyprland, with a 12-second auto-revert.
