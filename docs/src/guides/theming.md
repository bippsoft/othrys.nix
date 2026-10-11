# Theming

Every othrys module that draws colour reads one place, `othrys.theme`. It holds a
base16 palette, two fonts, window opacity, the polarity and the wallpaper. The
compositors, the bar, the prompt, the browser, the game overlay and the editor
dashboard take their colours from `othrys.theme.palette` and from nothing else.

Each value is nullable, and null has one meaning throughout. A module that finds
a null value writes nothing for that setting, and the application keeps its own
look. A host with no palette still gets a working compositor, bar and prompt.

`othrys.theme` is part of `nixosModules.default` and depends on no theming
framework. [Stylix](https://github.com/nix-community/stylix) is supported
through a separate export, described [below](#the-stylix-export), which themes
the applications othrys does not configure itself.

## Choosing a Scheme and a Polarity

A scheme is a named pair of palettes, one dark and one light. `scheme` picks the
pair and `polarity` picks the half.

```nix
othrys.theme = {
  scheme = "oxocarbon"; # the default
  polarity = "dark";    # "dark" or "light", dark by default
};
```

othrys ships one scheme, `oxocarbon`, in `modules/theme/schemes/oxocarbon.nix`.
A name that is in no scheme table fails an assertion that lists the names the
host does have.

## Adding a Scheme of Your Own

`othrys.theme.schemes` is an attribute set of schemes, and a host adds to it in
its own configuration. Nothing in this repository has to change. A scheme holds
`dark` and `light`, and each is an attribute set of colours written as six
hexadecimal digits with no `#`.

```nix
othrys.theme = {
  schemes.gruvbox = {
    dark = {
      base00 = "282828"; # Background
      base01 = "3c3836"; # Lighter background
      base02 = "504945"; # Selection
      base03 = "665c54"; # Comments
      base04 = "bdae93"; # Dark foreground
      base05 = "d5c4a1"; # Foreground
      base06 = "ebdbb2"; # Light foreground
      base07 = "fbf1c7"; # Lightest foreground
      base08 = "fb4934"; # Red
      base09 = "fe8019"; # Orange
      base0A = "fabd2f"; # Yellow
      base0B = "b8bb26"; # Green
      base0C = "8ec07c"; # Cyan
      base0D = "83a598"; # Blue
      base0E = "d3869b"; # Purple
      base0F = "d65d0e"; # Brown
    };
    light = {
      base00 = "fbf1c7";
      base01 = "ebdbb2";
      base02 = "d5c4a1";
      base03 = "bdae93";
      base04 = "665c54";
      base05 = "504945";
      base06 = "3c3836";
      base07 = "282828";
      base08 = "9d0006";
      base09 = "af3a03";
      base0A = "b57614";
      base0B = "79740e";
      base0C = "427b58";
      base0D = "076678";
      base0E = "8f3f71";
      base0F = "d65d0e";
    };
  };
  scheme = "gruvbox";
};
```

The sixteen base16 colours `base00` to `base0F` are required in both halves. The
eight base24 colours `base10` to `base17` are optional. A palette that lacks a
required colour, or holds a key outside those twenty-four, is refused under the
option's own name. Definitions of `schemes` merge, so adding a scheme leaves
`oxocarbon` available, and a host can change one colour of a shipped scheme
without restating the rest.

```nix
othrys.theme.schemes.oxocarbon.dark.base00 = lib.mkForce "000000";
```

The name `wallpaper` is reserved, since `scheme = "wallpaper"` has
[another meaning](#colour-from-the-wallpaper).

## Setting a Palette Directly

`othrys.theme.palette` is the value the modules read. Its default is the chosen
scheme at the chosen polarity, and a host can set it to any palette of the same
shape, from any source that produces one.

```nix
othrys.theme.palette = builtins.fromJSON (builtins.readFile ./palette.json);
```

A palette set this way reaches the othrys modules and does not reach Stylix,
which takes its colours from the scheme table. A host that uses the Stylix
export defines a scheme instead.

`othrys.theme.colors` is derived from the palette and is not set. A module that
needs the colour with a leading `#` reads `colors.withHashtag.<name>`, and one
that needs the red, green and blue channels as integers reads
`colors.rgb.<name>`.

## Fonts and Opacity

```nix
othrys.theme = {
  fonts.sansSerif = {
    name = "Inter";
    package = pkgs.inter;
  };
  fonts.monospace = {
    name = "JetBrainsMono Nerd Font";
    package = pkgs.nerd-fonts.jetbrains-mono;
  };
  opacity.terminal = 0.95;
};
```

Each font is a family name and, optionally, the package that provides it, which
othrys adds to `fonts.packages`. The bar reads `fonts.sansSerif`. Both fonts and
the opacity are null by default.

## Wallpapers

`othrys.theme.wallpaper` holds the wallpaper, and `othrys.desktop.wallpaper`
draws it with [wpaperd](https://github.com/danyspin97/wpaperd) under Hyprland
and niri alike. The daemon starts by itself on a host that runs an othrys
compositor and declares a wallpaper, as the
[desktop page](../modules/desktop.md#wallpaper) describes. No image ships with
this library, so a host provides its own.

### The Forms of a Source

`source` is null by default, which sets no wallpaper. The three other forms
differ in where the images live.

A Nix path is one image. It is copied into the store, so the wallpaper is part
of the system and changes with a rebuild. A package that builds an image is
accepted in the same place.

```nix
othrys.theme.wallpaper.source = ./wallpaper.png;
```

A list of images is a set the daemon picks from. Each image is copied into the
store, and othrys builds a directory of links to them for the daemon to read.

```nix
othrys.theme.wallpaper.source = [
  ./wallpapers/dawn.png
  ./wallpapers/noon.png
  ./wallpapers/dusk.png
];
```

A string is a directory the daemon reads while the session runs. It starts with
`/` or with `~/`, which the daemon expands to the home directory. Nothing is
copied, so an image added to the directory is picked up without a rebuild.

```nix
othrys.theme.wallpaper.source = "~/Pictures/Wallpapers";
```

Any other value is refused when the option is read. That includes a relative
string, an empty list and a list that holds a run-time string.

### Rotation

`interval` is the time one image stays on screen, as a number of seconds or as
a duration such as `"30s"`, `"10m"` or `"1h 30m"`. Null, the default, keeps the
image the session started with. `order` is `random` by default, and `ascending`
or `descending` go through the file names in order. A list is linked under
names that carry each image's position, so `ascending` shows a list in the
order it is written.

```nix
othrys.theme.wallpaper = {
  source = "~/Pictures/Wallpapers";
  interval = "10m";
  order = "ascending";
};
```

Both options have an effect only when `source` is a list or a directory. With a
single image they are left out of the daemon's configuration. The daemon does
the rotating, and othrys adds no timer of its own.

`fill` decides how an image that does not match the screen is drawn. `center`,
the default, covers the screen and crops what does not fit. `fit` shows the
whole image with black borders, `fit-border-color` takes the border colour from
the image's edge, `stretch` changes the aspect ratio, and `tile` repeats the
image.

### Per-Monitor Overrides

`outputs` is keyed by the name the compositor gives a monitor, which
`hyprctl monitors` or `niri msg outputs` prints. Each entry holds the same
`source`, `interval`, `order` and `fill`. A value left out takes the one set for
every monitor, and a monitor with no entry uses the top-level settings as they
are.

```nix
othrys.theme.wallpaper = {
  source = "~/Pictures/Wallpapers";
  interval = "10m";

  outputs = {
    # the same directory and interval, shown whole on a portrait monitor
    "DP-2".fill = "fit";
    # one fixed image, which does not rotate
    "HDMI-A-1".source = ./wallpapers/dusk.png;
  };
};
```

A host can also declare a wallpaper for single monitors only and leave the
top-level `source` null. The monitors with no entry then show no wallpaper.

### The Primary Image

Some consumers need exactly one image that is known when the system is built.
`primary` is that image. It is `source` when `source` is one image and the
first element when `source` is a list, so a host with either form sets nothing
further.

A directory read at run time has no image that is known at evaluation, and
`primary` is null for it. A host that needs one names it.

```nix
othrys.theme.wallpaper = {
  source = "~/Pictures/Wallpapers";
  primary = ./wallpapers/dawn.png;
};
```

`primary` does not change what is drawn. It is read by
[colour from the wallpaper](#colour-from-the-wallpaper) and by the Stylix
export.

## The Stylix Export

`nixosModules.stylix` is the adapter between `othrys.theme` and Stylix.
`nixosModules.default` does not import it, so a host that wants Stylix imports
the adapter and the Stylix module together, and a host that does not imports
neither. `nixosModules.full` holds both, so a host built from it only sets the
option.

```nix
# flake.nix
inputs.stylix.follows = "othrys/stylix";

# the host's module list
modules = [
  inputs.othrys.nixosModules.default
  inputs.othrys.nixosModules.stylix
  inputs.stylix.nixosModules.stylix
  # ...
  {othrys.system.stylix.enable = true;}
];
```

With `othrys.system.stylix.enable` set, the adapter does four things.

- **It configures Stylix from the theme.** `stylix.base16Scheme` is the chosen
  scheme at the chosen polarity, `stylix.polarity` follows
  `othrys.theme.polarity`, and `stylix.image` is `othrys.theme.wallpaper.primary`.
- **It sets the taste values Stylix needs.** Fonts, font sizes, a cursor,
  opacities and an icon theme are each written with `mkDefault`, so a host
  replaces one with a plain assignment to the Stylix option.
- **It fills the theme back.** `othrys.theme.fonts` and `othrys.theme.opacity`
  default to the values Stylix ends up with, so the bar is drawn in the font
  Stylix gives every other application.
- **It carries the Stylix targets othrys modules need.** The Floorp target is
  switched on for the profile the Floorp module creates. While
  `othrys.desktop.wallpaper` is on, Stylix's `hyprland.hyprpaper`, `hyprpaper`
  and `wpaperd` targets are switched off, since othrys draws the wallpaper
  itself and two programs would draw over each other.

Stylix takes one image, so it is handed `primary` and never the list or the
directory. The targets that show an image, such as the lock screen, show that
one. With a run-time directory and no `primary`, `stylix.image` is null and
those targets show none, while the desktop wallpaper is drawn as declared.

Stylix then themes what othrys leaves alone, which includes the console,
Plymouth, GTK, the terminals and the cursor. `othrys.system.stylix.gui.enable`
follows `othrys.desktop.graphical`, and with it off only the console and
Plymouth targets remain, which suits a server. The adapter sets no Qt target.

A font or an opacity is changed on the Stylix side, and the theme follows.

```nix
stylix.fonts.monospace = {
  package = pkgs.nerd-fonts.fira-code;
  name = "FiraCode Nerd Font";
};
stylix.opacity.terminal = 1.0;
```

The adapter also exports the palette as `BASE00` to `BASE0F` and `COLOR_*`
session variables and installs `show-colors`, which prints the palette with its
hex values and a swatch of each colour.

`othrys.system.stylix.scheme`, `polarity` and `wallpaper` are the former names of
`othrys.theme.scheme`, `othrys.theme.polarity` and
`othrys.theme.wallpaper.source`. They still work on a host that imports the
adapter, and each prints a warning naming its replacement.

## Colour from the Wallpaper

`othrys.theme.scheme = "wallpaper"` derives the palette from
`othrys.theme.wallpaper.primary`, with `polarity` deciding between a dark and a
light result. Stylix holds the generator, so this value needs the Stylix export
with `othrys.system.stylix.enable` set. Without it the host fails an assertion
that names `nixosModules.stylix`, and without a wallpaper it fails one that
names `othrys.theme.wallpaper.source`. A `source` that is a directory read at
run time gives the generator no image, so such a host fails an assertion that
names `othrys.theme.wallpaper.primary` until it sets that option.

```nix
othrys.theme = {
  scheme = "wallpaper";
  polarity = "dark";
  wallpaper.source = ./wallpaper.png;
};
othrys.system.stylix.enable = true;
```

The palette is generated when the system is built and copied into
`othrys.theme.palette`, so the othrys modules and Stylix draw the same colours.
A new primary image takes effect at the next rebuild. othrys does not change
colours while the session runs, so a rotating wallpaper keeps the palette of
its primary image.

## Handing Colour to a Run-Time Tool

A tool that recolours the session while it runs, from the wallpaper or from the
time of day, needs othrys to write no colour of its own. Setting
`othrys.theme.scheme = null` leaves the palette null, and every module then
omits its colours. The compositors keep their own border colours, the bar and
the overlay keep their defaults, Floorp gets no stylesheet, and the editor
dashboard falls back to fixed neutral colours. The prompt keeps its layout and
names its colours by ANSI name, so it follows whatever the tool does to the
terminal's palette. Everything that is not colour stays themed. The bar still
reads `othrys.theme.fonts`, Floorp still follows `polarity` for its dark or
light variant, and the wallpaper option is unchanged. The Stylix export cannot
be enabled on such a host, since Stylix does not run without a palette.

## Oxocarbon Colour Reference

The dark half of `oxocarbon`, drawn from IBM's Carbon palette. The roles are the
ones the scheme file's own comments give.

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
