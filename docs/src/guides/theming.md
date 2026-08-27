# Theming

System-wide theming is managed by Stylix with base16 color schemes. Stylix lives in `modules/system/stylix.nix` under `othrys.system.stylix` because it themes everything, from CLI tools and terminals to GTK/Qt apps and boot screens.

## Changing the Theme

Edit your host config:

```nix
othrys.system.stylix = {
  enable = true;
  scheme = "oxocarbon";     # Filename without .yaml extension
  polarity = "dark";        # "dark" or "light"
  wallpaper = ./wallpaper.png; # optional, a path from your host; omit to leave it unset
};
```

## Available Themes

Themes are base16 YAML files in `assets/themes/{polarity}/`. The default is `oxocarbon` (dark).

Nixpkgs also provides many schemes via `pkgs.base16-schemes`.

## Adding a Custom Theme

Create a base16 YAML file at `assets/themes/{polarity}/{name}.yaml`:

```yaml
scheme: "My Theme"
author: "Author Name"
base00: "1a1b26"  # Background
base01: "1f2335"  # Lighter background
base02: "292e42"  # Selection
base03: "565f89"  # Comments
base04: "a9b1d6"  # Dark foreground
base05: "c0caf5"  # Foreground
base06: "c0caf5"  # Light foreground
base07: "d5d6db"  # Lightest foreground
base08: "f7768e"  # Red
base09: "ff9e64"  # Orange
base0A: "e0af68"  # Yellow
base0B: "9ece6a"  # Green
base0C: "7dcfff"  # Cyan
base0D: "7aa2f7"  # Blue
base0E: "bb9af7"  # Magenta
base0F: "db4b4b"  # Brown
```

## Wallpapers

The wallpaper is optional and host-specific, so no image ships with this
library. Set `othrys.system.stylix.wallpaper` to a path from your own host (for
example a file next to the host config, or a path from a wallpaper flake input).
Leave it unset (`null`, the default) to skip the wallpaper. The color scheme
still comes from `scheme`/`polarity`.

## Verifying Colors

Run `show-colors` in a terminal to display the current palette with hex values, RGB, and color swatches.

## Oxocarbon Color Reference

Inspired by IBM's Carbon Design System:

| Base | Role | Hex |
|------|------|-----|
| base00 | Background | `#161616` |
| base01 | Lighter BG | `#262626` |
| base02 | Selection | `#393939` |
| base03 | Comments | `#525252` |
| base04 | Dark FG | `#dde1e6` |
| base05 | Foreground | `#f2f4f8` |
| base06 | Light FG | `#ffffff` |
| base07 | Lightest FG | `#08bdba` |
| base08 | Red | `#ee5396` |
| base09 | Orange | `#fa4d56` |
| base0A | Yellow | `#f1c21b` |
| base0B | Green | `#42be65` |
| base0C | Cyan | `#08bdba` |
| base0D | Blue | `#78a9ff` |
| base0E | Magenta | `#be95ff` |
| base0F | Brown | `#d0aaff` |
