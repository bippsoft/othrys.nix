# flake/checks/vicinae-eval.nix
# CORE. What the Vicinae module writes, read back from evaluated hosts. A
# settings file the server cannot write, a theme nobody selects, a launcher
# chord that still opens wofi and a server that restarts after it was quit
# all evaluate cleanly, so each is compared here with what the module
# documents.
{
  lib,
  hostConfig,
  impermanenceModules,
  stylixModules,
  mkExpectations,
  rejectedWith,
  bootCore,
  functioningHost,
  accountNoHomeManager,
}: let
  host = extra:
    hostConfig [
      functioningHost
      extra
    ];

  user = "alice";
  home = cfg: cfg.home-manager.users.${user};
  vicinae = cfg: (home cfg).programs.vicinae;
  settings = cfg: (vicinae cfg).settings;
  unit = cfg: (home cfg).systemd.user.services.vicinae;

  hyprland = {
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.ashell.enable = true;
  };
  niri = {
    othrys.desktop.compositors.niri.enable = true;
    othrys.desktop.ashell.enable = true;
  };
  on = {othrys.desktop.vicinae.enable = true;};

  # Sixteen distinct colours, so every key of the theme names the one it
  # was mapped from.
  palette =
    lib.listToAttrs (map (d: lib.nameValuePair "base0${d}" (lib.toLower "0${d}0${d}0${d}"))
      ["0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "A" "B" "C" "D" "E" "F"]);

  hyprlandOn = host {imports = [hyprland on];};
  niriOn = host {imports = [niri on];};
  hyprlandOff = host hyprland;
  niriOff = host niri;
  launcherOff = host {
    imports = [hyprland on];
    othrys.desktop.vicinae.launcher = false;
  };
  hostLauncher = host {
    imports = [niri on];
    othrys.desktop.launcherCommand = ["fuzzel"];
  };
  override = host {
    imports = [hyprland on];
    othrys.desktop.vicinae.settings.favicon_service = "google";
  };
  themed = host {
    imports = [hyprland on];
    othrys.theme = {
      inherit palette;
      fonts.sansSerif.name = "Example Sans";
      opacity.popups = 0.9;
    };
  };
  unthemed = host {
    imports = [hyprland on];
    othrys.theme.scheme = null;
  };
  inputServer = host {
    imports = [hyprland on];
    othrys.desktop.vicinae.inputServer.enable = true;
  };
  stylix = host {
    imports = [hyprland on stylixModules];
    othrys.system.stylix.enable = true;
  };
  noSession = host on;
  noHistory = host {
    imports = [niri on];
    othrys.desktop.ashell.clipboard.enable = false;
  };

  # An account Home Manager does not manage, and a host with no named user.
  noHomeManager = hostConfig [
    accountNoHomeManager
    on
    {othrys.desktop.graphical = true;}
  ];
  anonymous = hostConfig [
    bootCore
    on
    {
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
      othrys.desktop.graphical = true;
      # The keyring follows the graphical signal, and it is off so this
      # host reads the Vicinae module alone.
      othrys.desktop.keyring.enable = false;
    }
  ];

  # An impermanence host, in the shape eval-persistence uses. No disk layout
  # is imported, so the wipe is given its device by hand and the two volumes
  # impermanence needs for boot are named.
  persisted = host {
    imports = [hyprland on impermanenceModules];
    fileSystems = {
      "/nix" = {
        device = "/dev/disk/by-label/nix";
        fsType = "btrfs";
      };
      "/persist" = {
        device = "/dev/disk/by-label/persist";
        fsType = "btrfs";
      };
    };
    othrys.system = {
      impermanence = {
        enable = true;
        device = "/dev/disk/by-partlabel/root";
      };
      persistence.enable = true;
      shell.zsh.enable = true;
    };
  };
  userDirs = cfg: cfg.environment.persistence.${cfg.othrys.system.impermanence.persistRoot}.users.${user}.directories;
  pathOf = entry: entry.dirPath or entry.directory;
  persistedAt = cfg: rel: mode: builtins.any (entry: pathOf entry == "/home/${user}/${rel}" && entry.mode == mode) (userDirs cfg);
  persists = cfg: rel: builtins.any (entry: pathOf entry == "/home/${user}/${rel}") (userDirs cfg);

  isVicinae = p: (p.pname or "") == "vicinae";
  hyprlandLua = cfg: (home cfg).xdg.configFile."hypr/hyprland.lua".text;
  ashellToml = cfg: (home cfg).home.file.".config/ashell/config.toml".text;
  niriLauncher = cfg: (home cfg).programs.niri.settings.binds."Mod+D".action.spawn;
  isToggle = argv: builtins.length argv == 2 && lib.hasSuffix "/bin/vicinae" (builtins.head argv) && lib.last argv == "toggle";
  wofiBind = ''hl.bind((mainMod .. " + D"), (hl.dsp.exec_cmd("wofi --show drun")))'';
  niriSpawn = chord: cfg: (home cfg).programs.niri.settings.binds.${chord}.action.spawn or null;
  opens = command: argv: lib.hasSuffix "/bin/vicinae" (builtins.head argv) && lib.last argv == "vicinae://launch/${command}?toggle=true";
  installs = name: cfg: builtins.any (p: (p.pname or "") == name) (home cfg).home.packages;
in
  mkExpectations "othrys-eval-vicinae" {
    "Vicinae is in the user's packages" = builtins.any isVicinae (home hyprlandOn).home.packages;
    "Vicinae is not in the system packages" = !(builtins.any isVicinae hyprlandOn.environment.systemPackages);

    "telemetry is off" = (settings hyprlandOn).telemetry.system_info == false;
    "no favicon service is asked" = (settings hyprlandOn).favicon_service == "none";
    "the launcher opens at the root search" = (settings hyprlandOn).pop_to_root_on_close == true;
    "the input helper is off by default" = (settings hyprlandOn).input_server.enabled == false;
    "Vicinae records no clipboard while cliphist does" = (settings hyprlandOn).providers.clipboard.preferences.monitoring == false;
    "Vicinae records the clipboard without the bar's history" =
      !((settings noHistory) ? providers) || !((settings noHistory).providers ? clipboard);
    "settings.json is left for Vicinae to write" =
      (vicinae hyprlandOn).mutableSettings
      && (home hyprlandOn).xdg.configFile ? "vicinae/home-manager.json"
      && !((home hyprlandOn).xdg.configFile ? "vicinae/settings.json");
    "one overridden key takes the host's value" = (settings override).favicon_service == "google";
    "the other curated keys stay beside the override" =
      (settings override).pop_to_root_on_close == true && (settings override).telemetry.system_info == false;

    "the palette becomes the othrys theme" = let
      t = (vicinae themed).themes.othrys;
    in
      t.colors.core.background
      == "#000000"
      && t.colors.core.foreground == "#050505"
      && t.colors.core.secondary_background == "#010101"
      && t.colors.core.border == "#020202"
      && t.colors.core.accent == "#0d0d0d"
      && t.colors.accents.red == "#080808"
      && t.colors.accents.purple == "#0e0e0e"
      && t.colors.list.item.hover.background == "#010101"
      && t.colors.list.item.selection.background == "#020202"
      && t.meta.variant == "dark"
      && t.meta.inherits == "vicinae-dark";
    "both theme names select the othrys theme" =
      (settings themed).theme.dark.name == "othrys" && (settings themed).theme.light.name == "othrys";
    "the sans-serif font is the interface font" = (settings themed).font.normal.family == "Example Sans";
    "no palette writes no theme and selects none" = (vicinae unthemed).themes == {} && !((settings unthemed) ? theme);
    "no font leaves Vicinae its own" = !((settings unthemed) ? font);
    "Hyprland takes the keyboard on demand" =
      (settings hyprlandOn).launcher_window.layer_shell.keyboard_interactivity == "on_demand";
    "Niri keeps Vicinae's exclusive keyboard" = !((settings niriOn) ? launcher_window);
    "the launcher takes the opacity of popups" = (settings themed).launcher_window.opacity == 0.9;
    "no theme opacity leaves the window opaque" = !((settings hyprlandOn) ? launcher_window) || !((settings hyprlandOn).launcher_window ? opacity);
    "Stylix's own Vicinae target is off" = !(home stylix).stylix.targets.vicinae.enable;
    "the othrys theme is selected under Stylix" = (settings stylix).theme.dark.name == "othrys";

    "the server starts with the graphical session" = (unit hyprlandOn).Install.WantedBy == ["graphical-session.target"];
    "the server stops with the graphical session" = (unit hyprlandOn).Unit.PartOf == ["graphical-session.target"];
    "the server runs only in a Wayland session" = (unit hyprlandOn).Unit.ConditionEnvironment == "WAYLAND_DISPLAY";
    "a server quit from the tray stays down" = (unit hyprlandOn).Service.Restart == "on-failure";
    "the server reads the declared settings" = builtins.any (lib.hasInfix "VICINAE_OVERRIDES=") (unit hyprlandOn).Service.Environment;

    "the input helper is a capability wrapper" =
      inputServer.security.wrappers.vicinae-input-server.capabilities == "cap_dac_override+ep";
    "the input helper loads uinput" = builtins.elem "uinput" inputServer.boot.kernelModules;
    "the server is pointed at the wrapper" =
      builtins.elem "VICINAE_INPUT_SERVER_BIN=/run/wrappers/bin/vicinae-input-server" (unit inputServer).Service.Environment;
    "the input helper is switched on in the settings" = (settings inputServer).input_server.enabled == true;
    "no wrapper exists by default" = !(hyprlandOn.security.wrappers ? vicinae-input-server);

    "Hyprland's launcher chord toggles Vicinae" =
      isToggle hyprlandOn.othrys.desktop.launcherCommand
      && lib.hasInfix "/bin/vicinae toggle\")))" (hyprlandLua hyprlandOn);
    "Niri's launcher chord toggles Vicinae" = isToggle (niriLauncher niriOn);
    "the bar's launcher button toggles Vicinae" = lib.hasInfix "/bin/vicinae toggle\"\n" (ashellToml hyprlandOn);
    "Hyprland keeps wofi without Vicinae" = lib.hasInfix wofiBind (hyprlandLua hyprlandOff);
    "Niri keeps wofi without Vicinae" = niriLauncher niriOff == ["wofi" "--show" "drun"];
    "the bar keeps wofi without Vicinae" = lib.hasInfix "command = \"wofi --show drun\"\n" (ashellToml niriOff);
    "launcher = false keeps wofi with Vicinae on" = lib.hasInfix wofiBind (hyprlandLua launcherOff);
    "a host's own launcher command wins over Vicinae" = niriLauncher hostLauncher == ["fuzzel"];

    "the emoji chord opens Vicinae's emoji search" = opens "core/search-emojis" (niriSpawn "Mod+E" niriOn);
    "the file search chord opens Vicinae's file search" = opens "files/search" (niriSpawn "Mod+Shift+F" niriOn);
    "the clipboard history is shown in vicinae dmenu" =
      lib.hasInfix "/bin/vicinae dmenu | " (lib.last (niriSpawn "Mod+Shift+V" niriOn))
      && lib.hasInfix "/bin/vicinae dmenu | " (ashellToml niriOn);
    "the run chord is unbound with Vicinae" = niriSpawn "Mod+Shift+D" niriOn == null;
    "Hyprland's emoji chord opens Vicinae" = lib.hasInfix "vicinae://launch/core/search-emojis?toggle=true" (hyprlandLua hyprlandOn);
    "Vicinae leaves wofi, rofimoji and wtype uninstalled" =
      !(installs "wofi" niriOn || installs "rofimoji" niriOn || installs "wtype" niriOn);
    "launcher = false keeps wofi installed for the launcher alone" =
      installs "wofi" launcherOff && !(installs "rofimoji" launcherOff);

    "settings.json is persisted" = persists persisted ".config/vicinae";
    "the clipboard history is persisted at mode 0700" = persistedAt persisted ".local/share/vicinae" "0700";
    "the onboarding state is persisted at mode 0700" = persistedAt persisted ".local/state/vicinae" "0700";
    "the cache is not persisted" = !(persists persisted ".cache/vicinae");

    "a host with no graphical session is refused" = rejectedWith "othrys.desktop.vicinae requires a graphical session" noSession;
    "a host without Home Manager gets no Home Manager configuration" =
      !(noHomeManager ? home-manager)
      && builtins.any (w: lib.hasInfix "skipped for: " w && lib.hasInfix "desktop.vicinae" w) noHomeManager.warnings;
    "a host without Home Manager gets no system package or unit" =
      !(builtins.any isVicinae noHomeManager.environment.systemPackages)
      && !(noHomeManager.systemd.user.services ? vicinae);
    "a host with no named user evaluates" = anonymous.system.build.toplevel.drvPath != null;
    "a host with no named user gets no account" = !(anonymous.users.users ? alice);
  }
