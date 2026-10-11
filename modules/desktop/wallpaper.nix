# modules/desktop/wallpaper.nix
# Draws othrys.theme.wallpaper under either compositor, with wpaperd
#
# The theme says what the wallpaper is, and this module is the one place that
# draws it. wpaperd speaks the layer-shell protocol both compositors
# implement, so one daemon serves Hyprland and niri alike. It also holds the
# rotation, which leaves this module with nothing to do but render its
# configuration file.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.desktop.wallpaper;
  wallpaper = config.othrys.theme.wallpaper;
  compositorEnabled = config.othrys.desktop.compositors.hyprland.enable || config.othrys.desktop.compositors.niri.enable;

  # A string outside the store is a directory the daemon reads while the
  # session runs. Every other source is one image or a list of them, already
  # in the store or copied there when it is interpolated.
  storePrefix = "${builtins.storeDir}/";
  readAtRunTime = source: builtins.isString source && !lib.hasPrefix storePrefix source;

  # The daemon takes one image or one directory, so a list becomes a
  # directory of copies. Each copy keeps the file name of its image, since
  # the daemon tells an image by its extension, and carries its position in
  # front, which makes the daemon's ascending order the order of the list. A
  # store path's hash is dropped from the name, and so is the string context.
  linkName = index: image: let
    base = builtins.unsafeDiscardStringContext (baseNameOf (toString image));
    unhashed = builtins.match "[0-9a-z]{32}-(.+)" base;
  in "${lib.fixedWidthNumber 3 index}-${
    if unhashed == null
    then base
    else builtins.head unhashed
  }";
  # The images are copied, not linked. A directory of symbolic links depends
  # on how the daemon walks it, and a copy of a few images costs little.
  imageDirectory = images:
    pkgs.runCommand "othrys-wallpapers" {} (''
        mkdir -p "$out"
      ''
      + lib.concatStrings (lib.imap0 (index: image: ''
          cp --no-preserve=mode ${lib.escapeShellArg "${image}"} "$out"/${lib.escapeShellArg (linkName index image)}
        '')
        images));

  # One section of the daemon's configuration. `duration` and `sorting`
  # belong to a path that is a directory, so a single image gets neither.
  section = {
    source,
    interval,
    order,
    fill,
  }: let
    several = builtins.isList source || readAtRunTime source;
  in
    {
      path =
        if builtins.isList source
        then "${imageDirectory source}"
        else "${source}";
      mode = fill;
    }
    // lib.optionalAttrs several {sorting = order;}
    // lib.optionalAttrs (several && interval != null) {
      duration =
        if builtins.isInt interval
        then "${toString interval}s"
        else interval;
    };

  # A monitor's entry with every null value replaced by the one set for all
  # monitors. Each monitor is rendered whole, so the file never depends on
  # how the daemon itself inherits between sections.
  resolve = output:
    lib.genAttrs ["source" "interval" "order" "fill"] (
      name:
        if output.${name} != null
        then output.${name}
        else wallpaper.${name}
    );
  outputSections =
    lib.mapAttrs (_: section)
    (lib.filterAttrs (_: output: output.source != null) (lib.mapAttrs (_: resolve) wallpaper.outputs));

  # `any` is the section the daemon applies to every monitor that has none of
  # its own.
  settings =
    lib.optionalAttrs (wallpaper.source != null) {
      any = section {inherit (wallpaper) source interval order fill;};
    }
    // outputSections;

  declared = wallpaper.source != null || builtins.any (output: output.source != null) (builtins.attrValues wallpaper.outputs);
in {
  # ANCHOR: wallpaper-options
  options.othrys.desktop.wallpaper = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.othrys.desktop.graphical && compositorEnabled && declared;
      defaultText = lib.literalMD "true on a graphical host with an othrys compositor module enabled and a wallpaper declared, in `othrys.theme.wallpaper.source` or for a monitor in `othrys.theme.wallpaper.outputs`";
      example = false;
      description = ''
        Whether to draw `othrys.theme.wallpaper` with wpaperd, as a user
        service of the graphical session. It is on by default wherever an
        othrys compositor runs and a wallpaper is declared. A host that draws
        its wallpaper with another program turns it off, since two programs
        would draw over each other.
      '';
    };
  };
  # ANCHOR_END: wallpaper-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = declared;
        message = "othrys.desktop.wallpaper: no wallpaper is declared, so the daemon has nothing to draw. Set othrys.theme.wallpaper.source, or the source of a monitor in othrys.theme.wallpaper.outputs.";
      }
      {
        assertion = !(wallpaper.outputs ? any) && !(wallpaper.outputs ? default);
        message = "othrys.theme.wallpaper.outputs: \"any\" and \"default\" are section names the wallpaper daemon reserves, and neither names a monitor. Set the options under othrys.theme.wallpaper for every monitor.";
      }
    ];

    # The unit Home Manager writes is wanted by graphical-session.target and
    # stops with it, so the daemon starts under either compositor and under
    # no other session.
    othrys.internal.homeConfig."desktop.wallpaper" = {
      services.wpaperd = {
        enable = true;
        inherit settings;
      };
    };
  };
}
