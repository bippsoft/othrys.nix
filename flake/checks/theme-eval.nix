# flake/checks/theme-eval.nix
# CORE. The theme interface, read back from evaluated hosts. Every module
# that draws colour reads othrys.theme, and a graphical host has to evaluate
# with no Stylix module imported at all, which is the shape every host of
# this file has unless it lists the adapter itself. A palette that reaches
# the compositor and the prompt, a null palette that leaves both working, a
# scheme the host defines and a scheme name that is in no table all evaluate
# to something, so each is compared here with what the option documents.
# The hosts with the adapter show that Stylix is handed the same palette the
# modules read and that the theme takes its font from Stylix.
#
# `scheme = "wallpaper"` with an image is left out. Its palette comes from a
# build, and an evaluation check does not run one.
{
  lib,
  hostConfig,
  mkExpectations,
  rejectedWith,
  functioningHost,
  stylixModules,
}: let
  oxocarbon = import ../../modules/theme/schemes/oxocarbon.nix;

  # A complete palette that is in no scheme othrys ships.
  example = {
    base00 = "101010";
    base01 = "202020";
    base02 = "303030";
    base03 = "404040";
    base04 = "505050";
    base05 = "d0d0d0";
    base06 = "e0e0e0";
    base07 = "f0f0f0";
    base08 = "aa0001";
    base09 = "aa5502";
    base0A = "aaaa03";
    base0B = "00aa04";
    base0C = "00aaa5";
    base0D = "0000a6";
    base0E = "aa00a7";
    base0F = "aa55a8";
  };
  exampleScheme = {
    othrys.theme.schemes.example = {
      dark = example;
      light = example // {base00 = "fafafa";};
    };
  };

  # The five modules that draw colour, on a graphical host.
  graphical = {
    othrys.system.shell.starship.enable = true;
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.ashell.enable = true;
    othrys.apps.floorp.enable = true;
    othrys.apps.gaming.mangohud.enable = true;
  };
  # The compositor and the prompt alone, for the hosts that vary the theme
  # and read nothing else.
  small = {
    othrys.system.shell.starship.enable = true;
    othrys.desktop.compositors.hyprland.enable = true;
  };

  themed = hostConfig [functioningHost graphical];
  unthemed = hostConfig [functioningHost graphical {othrys.theme.scheme = null;}];

  host = extra: hostConfig [functioningHost small extra];
  ownScheme = host {
    imports = [exampleScheme];
    othrys.theme.scheme = "example";
  };
  light = host {othrys.theme.polarity = "light";};
  direct = host {
    othrys.theme = {
      scheme = null;
      palette = example;
    };
  };
  unknown = host {othrys.theme.scheme = "absent";};
  wallpaperAlone = host {othrys.theme.scheme = "wallpaper";};
  # Two base16 colours short. The type refuses it when the palette is read,
  # which aborts the read, so it is tried instead of asserted on.
  incomplete =
    builtins.tryEval
    (host {
      othrys.theme = {
        scheme = null;
        palette = builtins.removeAttrs example ["base0E" "base0F"];
      };
    }).othrys.theme.palette.base00;

  adapter = {
    imports = [stylixModules];
    othrys.system.stylix.enable = true;
  };
  withStylix = host {imports = [adapter];};
  withStylixLight = host {
    imports = [adapter];
    othrys.theme.polarity = "light";
  };
  wallpaperNoImage = host {
    imports = [adapter];
    othrys.theme.scheme = "wallpaper";
  };
  # The three names the adapter's options had before they moved.
  renamed = host {
    imports = [adapter exampleScheme];
    othrys.system.stylix = {
      scheme = "example";
      polarity = "light";
      wallpaper = ./theme-eval.nix;
    };
  };

  user = "alice";
  home = cfg: cfg.home-manager.users.${user};
  borders = cfg: (home cfg).wayland.windowManager.hyprland.settings.config.general;
  prompt = cfg: (home cfg).programs.starship.settings;
  ashellToml = cfg: (home cfg).home.file.".config/ashell/config.toml".text;
  floorp = cfg: (home cfg).programs.floorp;
  overlay = cfg: (home cfg).programs.mangohud.settings;
  evaluates = cfg: cfg.system.build.toplevel.drvPath != null;
  renameWarning = name: cfg: builtins.any (lib.hasInfix "othrys.system.stylix.${name}") cfg.warnings;
in
  mkExpectations "othrys-eval-theme" {
    "a graphical host evaluates with no Stylix module imported" = evaluates themed && !(themed ? stylix);
    "the default palette is oxocarbon dark" = themed.othrys.theme.palette == oxocarbon.dark;
    "the compositor border reads the palette" = (borders themed)."col.active_border" == "rgb(${oxocarbon.dark.base06})" && (borders themed)."col.inactive_border" == "rgb(${oxocarbon.dark.base01})";
    "the prompt reads the palette" = (prompt themed).directory.style == "#${oxocarbon.dark.base0D}" && (prompt themed).character.success_symbol == "[❯](bold #${oxocarbon.dark.base0B})";
    "the bar reads the palette" = lib.hasInfix "\nbase = \"#${oxocarbon.dark.base00}\"\n" (ashellToml themed);
    "the bar names no font when the theme has none" = !lib.hasInfix "font_name" (ashellToml themed);
    "the browser reads the palette" = lib.hasInfix "--theme-bg: #${oxocarbon.dark.base00} !important;" (floorp themed).profiles.default.userChrome && lib.hasInfix "rgba(22, 22, 22, 0.85)" (floorp themed).profiles.default.userChrome;
    "the overlay reads the palette" = (overlay themed).text_color == oxocarbon.dark.base05;

    "the same host evaluates with no palette" = evaluates unthemed && unthemed.othrys.theme.palette == null && unthemed.othrys.theme.colors == null;
    "without a palette the prompt uses ANSI names" = (prompt unthemed).directory.style == "blue" && (prompt unthemed).git_branch.style == "green" && (prompt unthemed).hostname.style == "purple" && (prompt unthemed).character.error_symbol == "[❯](bold red)";
    "without a palette the prompt keeps its layout" = (prompt unthemed).right_format == "$time" && (prompt unthemed).git_branch.format == (prompt themed).git_branch.format;
    "without a palette the compositor writes no border colour" = !((borders unthemed) ? "col.active_border") && (borders unthemed).border_size == 1;
    "without a palette the bar still renders, with no colour" = lib.hasInfix "\n[appearance.bar]\n" (ashellToml unthemed) && !lib.hasInfix "background_color" (ashellToml unthemed) && !lib.hasInfix "workspace_colors" (ashellToml unthemed);
    "without a palette the browser keeps its policies and gets no stylesheet" = (floorp unthemed).policies.ExtensionSettings."*".installation_mode == "blocked" && (floorp unthemed).profiles.default.userChrome == "" && !((floorp unthemed).profiles.default.settings ? "browser.display.background_color");
    "without a palette the overlay keeps its layout and gets no colour" = (overlay unthemed).position == "top-right" && !((overlay unthemed) ? text_color);

    "a scheme the host defines is picked up" = ownScheme.othrys.theme.palette == example && (prompt ownScheme).directory.style == "#${example.base0D}";
    "a host scheme leaves oxocarbon in the table" = ownScheme.othrys.theme.schemes ? oxocarbon;
    "polarity picks the light palette" = light.othrys.theme.palette == oxocarbon.light && (borders light)."col.active_border" == "rgb(${oxocarbon.light.base06})";
    "a palette set directly is the one the modules read" = (prompt direct).directory.style == "#${example.base0D}";
    "the hashed and the channel forms are derived from the palette" =
      direct.othrys.theme.colors.withHashtag.base08
      == "#aa0001"
      && direct.othrys.theme.colors.rgb.base09
      == {
        r = 170;
        g = 85;
        b = 2;
      };
    "a palette short of a base16 colour is refused" = !incomplete.success;
    "an unknown scheme name is rejected" = rejectedWith "is not a scheme in othrys.theme.schemes" unknown;
    "the wallpaper scheme without the adapter is rejected" = rejectedWith "nixosModules.stylix" wallpaperAlone;
    "a named scheme is not asked for the adapter" = !rejectedWith "nixosModules.stylix" themed;

    "the adapter hands Stylix the chosen palette" = withStylix.stylix.enable && withStylix.stylix.base16Scheme == withStylix.othrys.theme.palette && withStylix.stylix.base16Scheme == oxocarbon.dark;
    "the adapter follows the polarity" = withStylixLight.stylix.polarity == "light" && withStylixLight.stylix.base16Scheme == oxocarbon.light;
    "the theme takes its sans-serif font from Stylix" = withStylix.othrys.theme.fonts.sansSerif.name == withStylix.stylix.fonts.sansSerif.name;
    "the theme takes its monospace font from Stylix" = withStylix.othrys.theme.fonts.monospace.name == withStylix.stylix.fonts.monospace.name;
    "the theme takes its opacity from Stylix" = withStylix.othrys.theme.opacity.terminal == withStylix.stylix.opacity.terminal;
    "the compositor reads the same palette beside Stylix" = (borders withStylix)."col.active_border" == "rgb(${oxocarbon.dark.base06})";
    "the wallpaper scheme with the adapter and no image is rejected" = rejectedWith "othrys.theme.wallpaper.source is not set" wallpaperNoImage && !rejectedWith "nixosModules.stylix" wallpaperNoImage;

    "the old scheme option still sets the scheme" = renamed.othrys.theme.scheme == "example" && renamed.stylix.base16Scheme == (example // {base00 = "fafafa";});
    "the old polarity option still sets the polarity" = renamed.othrys.theme.polarity == "light" && renamed.stylix.polarity == "light";
    "the old wallpaper option still sets the wallpaper" = toString renamed.othrys.theme.wallpaper.source == toString ./theme-eval.nix;
    "each old name warns" = renameWarning "scheme" renamed && renameWarning "polarity" renamed && renameWarning "wallpaper" renamed;
  }
