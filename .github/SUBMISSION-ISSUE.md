### Repository URL

https://github.com/faperac/omarchy-displays

### Category

Hardware

### Tags

hyprland, bar, system

### Suggest a missing tag

_No response_

### Maintainer notes

Bar widget. The only side effect is "Apply", which runs the bundled
`bin/omarchy-displays --from-native`: it backs up `~/.config/hypr/monitors.lua`
to `monitors.lua.bak.<ts>`, rewrites only a delimited managed block, then
`hyprctl reload`. This runs only on an explicit button press and has a
12-second auto-revert. Runtime deps: `quickshell`, `jq` (both ship with
Omarchy). No package installs, no `sudo`/`pkexec`, no installer script.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
