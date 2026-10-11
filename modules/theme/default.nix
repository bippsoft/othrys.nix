# modules/theme/default.nix
# The theme every othrys module reads: a base16 palette, fonts, opacity and a wallpaper
#
# A module that draws colour reads othrys.theme.palette and nothing else. A
# null palette means the module writes no colour and the application keeps its
# own look, so a host with no palette still gets a compositor, a bar and a
# prompt. Nothing here depends on a theming framework. One that derives a
# palette or themes further applications is a separate module that fills
# these options.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.theme;

  base16Keys = map (digit: "base0${digit}") (lib.stringToCharacters "0123456789ABCDEF");
  base24Keys = map (digit: "base1${digit}") (lib.stringToCharacters "01234567");

  colour =
    lib.types.strMatching "[0-9a-fA-F]{6}"
    // {
      description = "colour as six hexadecimal digits, without a leading #";
    };
  colours = lib.types.attrsOf colour;

  # An attribute set of colours that holds every base16 key and may hold the
  # base24 ones. The keys are checked after the definitions are merged, so a
  # host can change one colour of a scheme in a definition of its own. A
  # missing key is reported under the option's name here, where a plain
  # attribute set would fail in whichever module first read the colour.
  paletteType = lib.mkOptionType {
    name = "base16Palette";
    description = "base16 palette (base00 to base0F, and optionally the base24 colours base10 to base17)";
    descriptionClass = "noun";
    check = builtins.isAttrs;
    merge = loc: defs: let
      merged = colours.merge loc defs;
      missing = builtins.filter (key: !(merged ? ${key})) base16Keys;
      unknown = lib.subtractLists (base16Keys ++ base24Keys) (builtins.attrNames merged);
    in
      if missing != []
      then throw "The option `${lib.showOption loc}' is missing the base16 colours ${lib.concatStringsSep ", " missing}."
      else if unknown != []
      then throw "The option `${lib.showOption loc}' holds ${lib.concatStringsSep ", " unknown}, and a palette holds only base00 to base0F and base10 to base17."
      else merged;
  };

  fontType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        example = "JetBrainsMono Nerd Font";
        description = "Family name of the font, as fontconfig knows it.";
      };
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression "pkgs.nerd-fonts.jetbrains-mono";
        description = "Package that provides the font. It is added to `fonts.packages`. Null installs nothing, for a font the host already has.";
      };
    };
  };

  opacityOption = surface:
    lib.mkOption {
      type = lib.types.numbers.between 0 1;
      default = 1.0;
      description = "Opacity of ${surface}, from 0 to 1.";
    };

  channel = offset: hex: lib.fromHexString (builtins.substring offset 2 hex);
in {
  options.othrys.theme = {
    schemes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          dark = lib.mkOption {
            type = paletteType;
            description = "The palette this scheme gives a dark host.";
          };
          light = lib.mkOption {
            type = paletteType;
            description = "The palette this scheme gives a light host.";
          };
        };
      });
      example = lib.literalExpression ''
        {
          gruvbox = {
            dark = {
              base00 = "282828";
              base01 = "3c3836";
              base02 = "504945";
              base03 = "665c54";
              base04 = "bdae93";
              base05 = "d5c4a1";
              base06 = "ebdbb2";
              base07 = "fbf1c7";
              base08 = "fb4934";
              base09 = "fe8019";
              base0A = "fabd2f";
              base0B = "b8bb26";
              base0C = "8ec07c";
              base0D = "83a598";
              base0E = "d3869b";
              base0F = "d65d0e";
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
        }
      '';
      description = ''
        The colour schemes a host can choose from, by name. Each scheme holds
        a `dark` and a `light` palette, and a palette is an attribute set of
        colours written as six hexadecimal digits with no `#`. The sixteen
        base16 colours `base00` to `base0F` are required. The eight base24
        colours `base10` to `base17` are optional.

        othrys defines `oxocarbon`. A host adds a scheme of its own by
        defining another name here with the same shape, as the example does,
        and selects it with `othrys.theme.scheme`. The definitions merge, so
        adding a scheme leaves `oxocarbon` in place. The name `wallpaper` is
        reserved, since `othrys.theme.scheme` gives it another meaning.
      '';
    };

    scheme = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "oxocarbon";
      example = "gruvbox";
      description = ''
        The scheme in use, as a name in `othrys.theme.schemes`.

        `"wallpaper"` derives the palette from
        `othrys.theme.wallpaper.source` when the system is built. othrys
        holds no generator of its own, so this value needs a module that
        provides one, as described in the theming guide.

        Null selects no scheme. `othrys.theme.palette` is then null unless
        the host sets it, and every othrys module leaves colour to the
        application.
      '';
    };

    polarity = lib.mkOption {
      type = lib.types.enum ["dark" "light"];
      default = "dark";
      description = "Whether the host is dark or light. It picks the half of the scheme that becomes the palette, and modules that tell an application which variant to use read it.";
    };

    palette = lib.mkOption {
      type = lib.types.nullOr paletteType;
      default =
        if cfg.scheme == null
        then null
        else cfg.schemes.${cfg.scheme}.${cfg.polarity} or null;
      defaultText = lib.literalMD "the scheme named by `othrys.theme.scheme`, at `othrys.theme.polarity`, or null when the scheme is null";
      example = lib.literalExpression "config.othrys.theme.schemes.oxocarbon.light";
      description = ''
        The palette every othrys module reads. It follows `scheme` and
        `polarity` by default, and a host can set it directly to a palette
        that belongs to no scheme.

        Null means no palette. A module then writes no colour, and the
        application keeps its own look.
      '';
    };

    colors = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      default =
        if cfg.palette == null
        then null
        else {
          withHashtag = lib.mapAttrs (_: hex: "#${hex}") cfg.palette;
          rgb =
            lib.mapAttrs (_: hex: {
              r = channel 0 hex;
              g = channel 2 hex;
              b = channel 4 hex;
            })
            cfg.palette;
        };
      defaultText = lib.literalMD "derived from `othrys.theme.palette`";
      description = ''
        The palette in the other forms a module needs, derived and not to be
        set. `withHashtag.<name>` is the colour with a leading `#`, and
        `rgb.<name>` holds its `r`, `g` and `b` channels as integers from 0
        to 255. Null when the palette is null. The plain six digits are
        `othrys.theme.palette.<name>`.
      '';
    };

    fonts = {
      sansSerif = lib.mkOption {
        type = lib.types.nullOr fontType;
        default = null;
        example = lib.literalExpression ''
          {
            name = "Inter";
            package = pkgs.inter;
          }
        '';
        description = "The sans-serif font for interface text, which the bar reads. Null leaves each application its own font.";
      };
      monospace = lib.mkOption {
        type = lib.types.nullOr fontType;
        default = null;
        example = lib.literalExpression ''
          {
            name = "JetBrainsMono Nerd Font";
            package = pkgs.nerd-fonts.jetbrains-mono;
          }
        '';
        description = "The monospace font for terminals and editors. Null leaves each application its own font.";
      };
    };

    opacity = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          terminal = opacityOption "terminal windows";
          applications = opacityOption "application windows";
          desktop = opacityOption "bars and widgets";
          popups = opacityOption "notifications and popups";
        };
      });
      default = null;
      example = {terminal = 0.95;};
      description = "Window opacity by kind of surface. Null leaves opacity to each application.";
    };

    wallpaper.source = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./wallpaper.png";
      description = ''
        The desktop wallpaper, as a single image. No image ships with this
        library, so a host provides its own. Null sets no wallpaper, and the
        palette still comes from `scheme` and `polarity`.
      '';
    };
  };

  # Set by a module that can derive a palette from the wallpaper. The
  # assertion below reads it, so `scheme = "wallpaper"` on a host with no such
  # module is refused by name.
  options.othrys.internal.wallpaperPalette = lib.mkOption {
    type = lib.types.bool;
    default = false;
    internal = true;
    description = "Whether a module on this host derives othrys.theme.palette from the wallpaper.";
  };

  config = {
    othrys.theme.schemes.oxocarbon = import ./schemes/oxocarbon.nix;

    assertions = [
      {
        assertion = cfg.scheme == null || cfg.scheme == "wallpaper" || cfg.schemes ? ${cfg.scheme};
        message = "othrys.theme.scheme is \"${toString cfg.scheme}\", which is not a scheme in othrys.theme.schemes (${lib.concatStringsSep ", " (builtins.attrNames cfg.schemes)}).";
      }
      {
        assertion = !(cfg.schemes ? wallpaper);
        message = "othrys.theme.schemes.wallpaper: the name is reserved, since othrys.theme.scheme = \"wallpaper\" derives the palette from the wallpaper. Give the scheme another name.";
      }
      {
        assertion = cfg.scheme != "wallpaper" || config.othrys.internal.wallpaperPalette;
        message = "othrys.theme.scheme = \"wallpaper\" derives the palette from the wallpaper, which othrys does through Stylix. Import nixosModules.stylix beside the Stylix module and set othrys.system.stylix.enable, or name a scheme in othrys.theme.schemes.";
      }
    ];

    fonts.packages = builtins.filter (package: package != null) (
      map (font:
        if font == null
        then null
        else font.package) [cfg.fonts.sansSerif cfg.fonts.monospace]
    );
  };
}
