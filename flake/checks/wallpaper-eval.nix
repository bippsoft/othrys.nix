# flake/checks/wallpaper-eval.nix
# CORE. What othrys.theme.wallpaper becomes, read back from evaluated hosts.
# The wallpaper daemon reads one file, and a section with the wrong key or a
# rotation interval beside a single image still evaluates. Each form of
# `source` is therefore compared here with the section the daemon is handed,
# together with the hosts that must get no daemon at all, the image the
# option names as primary and what the Stylix adapter does with it.
{
  lib,
  hostConfig,
  mkExpectations,
  rejectedWith,
  bootBase,
  functioningHost,
  stylixModules,
}: let
  # The images are only ever read as paths here, so any two files serve.
  first = ./wallpaper-eval.nix;
  second = ./theme-eval.nix;
  directory = "~/Pictures/Wallpapers";

  hyprland = {othrys.desktop.compositors.hyprland.enable = true;};
  niri = {othrys.desktop.compositors.niri.enable = true;};
  adapter = {
    imports = [stylixModules];
    othrys.system.stylix.enable = true;
  };
  host = extra: hostConfig [functioningHost extra];

  # One image, with an interval that has nothing to rotate through.
  one = host {
    imports = [hyprland];
    othrys.theme.wallpaper = {
      source = first;
      interval = "10m";
    };
  };
  # A list on the other compositor, with the interval as a number of seconds
  # and neither `order` nor `fill` at its default.
  several = host {
    imports = [niri];
    othrys.theme.wallpaper = {
      source = [first second];
      interval = 600;
      order = "descending";
      fill = "stretch";
    };
  };
  # A directory read at run time. One monitor changes the fill alone and
  # another takes a single image.
  runTime = host {
    imports = [hyprland];
    othrys.theme.wallpaper = {
      source = directory;
      interval = "30m";
      order = "ascending";
      outputs."DP-1".fill = "fit";
      outputs."HDMI-A-1".source = second;
    };
  };
  monitorOnly = host {
    imports = [hyprland];
    othrys.theme.wallpaper.outputs."DP-1".source = first;
  };
  none = host {imports = [hyprland];};
  forced = host {
    imports = [hyprland];
    othrys.desktop.wallpaper.enable = true;
  };
  noCompositor = host {
    othrys.desktop.graphical = true;
    othrys.theme.wallpaper.source = first;
  };
  headless = hostConfig [
    bootBase
    {
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
      othrys.theme.wallpaper.source = first;
    }
  ];

  withStylix = host {
    imports = [hyprland adapter];
    othrys.theme.wallpaper.source = [second first];
  };
  stylixRunTime = host {
    imports = [hyprland adapter];
    othrys.theme.wallpaper = {
      source = directory;
      primary = second;
    };
  };
  # The palette is asked of a directory that holds no image at evaluation.
  derivedFromDirectory = host {
    imports = [hyprland adapter];
    othrys.theme = {
      scheme = "wallpaper";
      wallpaper.source = directory;
    };
  };

  # The type refuses each of these when the option is read, which aborts the
  # read, so they are tried instead of asserted on.
  refused = source:
    !(builtins.tryEval
      (host {
        imports = [hyprland];
        othrys.theme.wallpaper = {inherit source;};
      }).othrys.theme.wallpaper.source).success;

  user = "alice";
  home = cfg: cfg.home-manager.users.${user};
  daemon = cfg: (home cfg).services.wpaperd;
  sections = cfg: (daemon cfg).settings;
  draws = cfg: cfg.othrys.desktop.wallpaper.enable && (daemon cfg).enable;
  primary = cfg: cfg.othrys.theme.wallpaper.primary;
  linked = path: lib.hasPrefix "${builtins.storeDir}/" path && lib.hasSuffix "-othrys-wallpapers" path;
in
  mkExpectations "othrys-eval-wallpaper" {
    "one image is drawn on every monitor, from the store" =
      draws one
      && sections one
      == {
        any = {
          path = "${first}";
          mode = "center";
        };
      };
    "an interval beside one image writes no duration" = !((sections one).any ? duration) && !((sections one).any ? sorting);
    "the daemon belongs to the graphical session" = (home one).systemd.user.services.wpaperd.Install.WantedBy == ["graphical-session.target"] && (home one).systemd.user.services.wpaperd.Unit.PartOf == ["graphical-session.target"];

    "a list is drawn under niri, from a directory of links" = draws several && linked (sections several).any.path;
    "an interval in seconds is written as a duration" = (sections several).any.duration == "600s";
    "order and fill reach the daemon under its own key names" = (sections several).any.sorting == "descending" && (sections several).any.mode == "stretch";

    "a directory read at run time is passed as written" =
      draws runTime
      && (sections runTime).any
      == {
        path = directory;
        mode = "center";
        sorting = "ascending";
        duration = "30m";
      };
    "a monitor inherits what it does not set" =
      (sections runTime)."DP-1"
      == {
        path = directory;
        mode = "fit";
        sorting = "ascending";
        duration = "30m";
      };
    "a monitor with one image of its own drops the rotation" =
      (sections runTime)."HDMI-A-1"
      == {
        path = "${second}";
        mode = "center";
      };
    "a wallpaper for one monitor alone starts the daemon with that section only" =
      draws monitorOnly
      && sections monitorOnly
      == {
        "DP-1" = {
          path = "${first}";
          mode = "center";
        };
      };

    "a host with no wallpaper runs no daemon" = !none.othrys.desktop.wallpaper.enable && !(daemon none).enable;
    "the daemon enabled with no wallpaper is rejected" = rejectedWith "othrys.desktop.wallpaper: no wallpaper is declared" forced;
    "a host with a wallpaper is not asked for one" = !rejectedWith "othrys.desktop.wallpaper" one;
    "a graphical host with no othrys compositor runs no daemon" = !noCompositor.othrys.desktop.wallpaper.enable && !(daemon noCompositor).enable;
    "a headless host runs no daemon" = !headless.othrys.desktop.wallpaper.enable;

    "primary is the image when source is one image" = toString (primary one) == toString first;
    "primary is the first image when source is a list" = toString (primary several) == toString first;
    "primary is null when source is a directory read at run time" = primary runTime == null;
    "primary is null when there is no source" = primary none == null;

    "the adapter hands Stylix the primary image" = withStylix.stylix.image == "${second}";
    "the adapter hands Stylix a primary set beside a run-time directory" = stylixRunTime.stylix.image == "${second}" && (sections stylixRunTime).any.path == directory;
    "Stylix starts no hyprpaper and writes no wpaperd section beside othrys" = let
      targets = (home withStylix).stylix.targets;
    in
      !targets.hyprland.hyprpaper.enable && !targets.hyprpaper.enable && !targets.wpaperd.enable && !(home withStylix).services.hyprpaper.enable;
    "the daemon draws the list on a host with the adapter" = draws withStylix && linked (sections withStylix).any.path && builtins.attrNames (sections withStylix) == ["any"];
    "colour from a run-time directory with no primary is rejected" = rejectedWith "Set othrys.theme.wallpaper.primary" derivedFromDirectory;
    "a host with an image is not asked for a primary" = !rejectedWith "othrys.theme.wallpaper.primary" withStylix;

    "a relative directory is refused" = refused "Pictures/Wallpapers";
    "an empty list is refused" = refused [];
    "a value that is neither an image, a list nor a directory is refused" = refused 5;
  }
