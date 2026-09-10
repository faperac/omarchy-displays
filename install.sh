#!/usr/bin/env bash
# Install omarchy-displays:
#   - the Omarchy bar plugin  (faperac.displays)  -> the header button
#   - the standalone CLI / GUI (omarchy-displays)
#
# Usage:  ./install.sh [left|center|right]      (bar section; default: right)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
section="${1:-right}"
case "$section" in
  left|center|right) ;;
  *) echo "Section must be left, center or right (got: $section)"; exit 1 ;;
esac

plugin_id="faperac.displays"
plugin_dir="${HOME}/.config/omarchy/plugins/${plugin_id}"
bindir="${HOME}/.local/bin"
appdir="${HOME}/.local/share/applications"

# ---- CLI + standalone GUI -------------------------------------------------
mkdir -p "$bindir" "$appdir"
chmod +x "$here/bin/omarchy-displays"
ln -sf "$here/bin/omarchy-displays" "$bindir/omarchy-displays"
sed "s|^Exec=omarchy-displays\$|Exec=$bindir/omarchy-displays|" \
  "$here/share/applications/omarchy-displays.desktop" > "$appdir/omarchy-displays.desktop"

# ---- bar plugin --------------------------------------------------------
mkdir -p "$plugin_dir"
cp -f "$here/manifest.json" "$here/BarWidget.qml" "$here/Panel.qml" "$here/logic.js" "$plugin_dir/"
# Bake the chosen section into the installed manifest's defaultSection.
sed -i "s/\"defaultSection\": \"[a-z]*\"/\"defaultSection\": \"$section\"/" "$plugin_dir/manifest.json"

echo "Installed:"
echo "  $plugin_dir/            (bar plugin: $plugin_id, section: $section)"
echo "  $bindir/omarchy-displays"
echo "  $appdir/omarchy-displays.desktop"
echo

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$plugin_dir" >/dev/null && echo "manifest: valid"
  echo "Enabling the bar widget…"
  omarchy plugin enable "$plugin_id" "$section" 2>/dev/null \
    || omarchy plugin enable "$plugin_id" 2>/dev/null || true
  omarchy bar move "$plugin_id" --section "$section" 2>/dev/null || true
  omarchy restart shell 2>/dev/null || true
  echo
  echo "Look for the 󰍹 icon in the $section of your bar. Move it later with:"
  echo "  omarchy bar move $plugin_id --section left|center|right --index N"
else
  echo "omarchy CLI not found — enable it manually:"
  echo "  omarchy plugin enable $plugin_id $section && omarchy restart shell"
fi
