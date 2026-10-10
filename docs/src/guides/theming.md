# Theming

System-wide theming is managed by Stylix from one color scheme. Stylix lives in `modules/system/stylix.nix` under `othrys.system.stylix` because it themes everything, from CLI tools and terminals to GTK apps and boot screens. The module sets the console, Plymouth and GTK targets and sets no Qt target.

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

Themes are YAML files in `assets/themes/{polarity}/`, in the tinted-theming
base24 layout. The repository ships `oxocarbon` for each polarity, and the
default is `oxocarbon` with `polarity = "dark"`.

`scheme` names a file in this repository, so it cannot point at a scheme from
`pkgs.base16-schemes`. A host that wants one of those assigns
`stylix.base16Scheme` with `lib.mkForce`, which replaces the path the module
writes.

## Adding a Custom Theme

A new theme is a file at `assets/themes/{polarity}/{name}.yaml` in this
repository or in a fork of it. The shipped files use this layout, where
`base00` to `base0F` are the base16 colors and `base10` to `base17` are the
extra base24 ones.

```yaml
system: "base24"
name: "My Theme"
author: "Author Name"
variant: "dark"
palette:
  base00: "1a1b26" # Background
  base01: "1f2335" # Lighter background
  base02: "292e42" # Selection
  base03: "565f89" # Comments
  base04: "a9b1d6" # Dark foreground
  base05: "c0caf5" # Foreground
  base06: "c0caf5" # Light foreground
  base07: "d5d6db" # Lightest foreground
  base08: "f7768e" # Red
  base09: "ff9e64" # Orange
  base0A: "e0af68" # Yellow
  base0B: "9ece6a" # Green
  base0C: "7dcfff" # Cyan
  base0D: "7aa2f7" # Blue
  base0E: "bb9af7" # Magenta
  base0F: "db4b4b" # Brown
  base10: "16161e"
  base11: "0f0f14"
  base12: "ff899d"
  base13: "faba4a"
  base14: "9fe044"
  base15: "4ae4f5"
  base16: "8db0ff"
  base17: "c7a9ff"
```

## Wallpapers

The wallpaper is optional and host-specific, so no image ships with this
library. Set `othrys.system.stylix.wallpaper` to a path from your own host (for
example a file next to the host config, or a path from a wallpaper flake input).
Leave it unset (`null`, the default) to skip the wallpaper. The color scheme
still comes from `scheme`/`polarity`.

## Fonts, Cursor and Opacity

The module picks fonts, font sizes, a cursor, opacities and an icon theme.
Each is written with `mkDefault`, so a host replaces one with a plain
assignment to the Stylix option.

```nix
stylix.fonts.monospace = {
  package = pkgs.nerd-fonts.fira-code;
  name = "FiraCode Nerd Font";
};
stylix.opacity.terminal = 1.0;
```

## Verifying Colors

Run `show-colors` in a terminal to display the current palette with hex values, RGB, and color swatches.

## Oxocarbon Color Reference

The dark scheme in `assets/themes/dark/oxocarbon.yaml`, drawn from IBM's Carbon
palette. The roles are the ones the file's own comments give.

| Base | Role | Hex |
|------|------|-----|
| base00 | Background | `#161616` |
| base01 | Lighter BG | `#262626` |
| base02 | Selection | `#393939` |
| base03 | Comments | `#525252` |
| base04 | Dark FG | `#6f6f6f` |
| base05 | Foreground | `#f4f4f4` |
| base06 | Light FG | `#ffffff` |
| base07 | Light BG | `#e0e0e0` |
| base08 | Red | `#fa4d56` |
| base09 | Orange | `#ff832b` |
| base0A | Yellow | `#f1c21b` |
| base0B | Green | `#42be65` |
| base0C | Cyan | `#3ddbd9` |
| base0D | Blue | `#4589ff` |
| base0E | Purple | `#be95ff` |
| base0F | Magenta | `#ff7eb6` |
| base10 | Bright black | `#525252` |
| base11 | Bright red | `#ff8389` |
| base12 | Bright green | `#6fdc8c` |
| base13 | Bright yellow | `#fddc69` |
| base14 | Bright blue | `#78a9ff` |
| base15 | Bright purple | `#d4bbff` |
| base16 | Bright cyan | `#08bdba` |
| base17 | Bright white | `#ffffff` |
