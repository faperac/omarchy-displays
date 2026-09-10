# Changelog

## Unreleased

- Fixed "Set as primary", which was a no-op for every layout. `setPrimary()`
  shifted the layout so the chosen monitor sat at (0,0), and the last step of
  `resolveAndNormalize()` shifted it straight back so the top-left monitor sat
  at (0,0) — the exact inverse. Normalization now anchors on the primary, which
  the model tracks explicitly instead of inferring from `x === 0 && y === 0`;
  the other monitors take negative coordinates, which Hyprland accepts.

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
