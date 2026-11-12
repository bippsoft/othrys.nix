# flake/checks/t3code-eval.nix
# CORE. What the t3code module installs, runs, opens and persists, read back
# from evaluated NixOS hosts. The agents it drives, the telemetry and update
# switches, the server's command line and the firewall rule for each listen
# mode are package arguments, wrapper flags, script text and firewall lists,
# and none of them fails evaluation when it is wrong.
{
  lib,
  hostConfig,
  mkExpectations,
  rejectedWith,
  functioningHost,
  accountNoHomeManager,
}: let
  host = extra:
    hostConfig [
      functioningHost
      {
        othrys.system.nix.allowUnfree = true;
        othrys.apps.ai = {
          codex.enable = true;
          claude-code.enable = true;
        };
      }
      extra
    ];
  t3 = settings: {othrys.apps.ai.t3code = {enable = true;} // settings;};
  headlessWith = settings: host (t3 ({mode = "headless";} // settings));

  headless = headlessWith {};
  # An account othrys creates without Home Manager, where the unit never
  # reaches the user and lingering would start a manager with nothing to run.
  noHome = hostConfig [
    accountNoHomeManager
    {
      othrys.system.nix.allowUnfree = true;
      othrys.apps.ai.codex.enable = true;
    }
    (t3 {mode = "headless";})
  ];
  desktop = host {
    othrys.desktop.graphical = true;
    othrys.apps.ai.t3code = {
      enable = true;
      mode = "desktop";
    };
  };
  telemetryOn = headlessWith {disableTelemetry = false;};
  lan = headlessWith {listen = "lan";};
  lanPort = headlessWith {
    listen = "lan";
    port = 4000;
  };
  tailnet = host {
    othrys.services.tailscale.enable = true;
    othrys.apps.ai.t3code = {
      enable = true;
      mode = "headless";
      listen = "tailscale";
    };
  };
  codexOnly = hostConfig [
    functioningHost
    {
      othrys.apps.ai.codex.enable = true;
      othrys.apps.ai.t3code = {
        enable = true;
        mode = "headless";
      };
    }
  ];

  unsetMode = host (t3 {});
  noAgents = hostConfig [functioningHost (t3 {mode = "headless";})];
  desktopNoSession = host (t3 {mode = "desktop";});
  desktopLan = host {
    othrys.desktop.graphical = true;
    othrys.apps.ai.t3code = {
      enable = true;
      mode = "desktop";
      listen = "lan";
    };
  };
  tailnetNoTailscale = headlessWith {listen = "tailscale";};
  off = host {othrys.desktop.graphical = true;};

  user = h: h.othrys.system.user.name;
  hmOf = h: h.home-manager.users.${user h};
  installed = h: pkg: builtins.any (p: (p.outPath or null) == pkg.outPath) (hmOf h).home.packages;
  wrapperScript = pkg: (pkg.drvAttrs.buildCommand or "") + (pkg.drvAttrs.postBuild or "");
  internal = h: h.othrys.internal.t3code;
  serveText = h: (internal h).serve.text;
  unit = h: (hmOf h).systemd.user.services.t3code;
  drvPaths = map (p: p.drvPath);
  providersOf = h: drvPaths (h.othrys.apps.ai.t3code.package.providerPackages or []);
  agent = h: name: h.othrys.internal.agents.${name};
  bare = h: name: h.othrys.apps.ai.${name}.package;
  # The headless host with the project-environment launcher turned off.
  unwrappedHost = host {
    othrys.apps.ai.projectEnvironment.enable = false;
    othrys.apps.ai.t3code = {
      enable = true;
      mode = "headless";
    };
  };

  headlessPath = builtins.head (unit headless).Service.Environment;
  pathEntries = lib.splitString ":" (lib.removePrefix "PATH=" headlessPath);
  tailnetPorts = h: h.networking.firewall.interfaces.${h.services.tailscale.interfaceName}.allowedTCPPorts or [];
  globalPorts = h: h.networking.firewall.allowedTCPPorts;

  dirs = list:
    map (directory: {
      inherit directory;
      mode = "0700";
    })
    list;
  persisted = h: h.othrys.internal.persist."apps.ai.t3code".user.directories;
  refusedByT3code = h: builtins.any (a: !a.assertion && lib.hasInfix "othrys.apps.ai.t3code" a.message) h.assertions;
in
  mkExpectations "othrys-eval-t3code" {
    "T3 Code is handed the codex and claude-code launchers, in that order" =
      providersOf headless
      == drvPaths [(agent headless "codex") (agent headless "claude-code")]
      && providersOf headless != drvPaths [(bare headless "codex") (bare headless "claude-code")];
    "with the launcher off T3 Code is handed the bare packages" =
      providersOf unwrappedHost == drvPaths [(bare unwrappedHost "codex") (bare unwrappedHost "claude-code")];
    "a host with codex alone hands T3 Code the codex package alone" =
      providersOf codexOnly == drvPaths [(agent codexOnly "codex")];

    "the user's profile installs the wrapped t3" = installed headless (internal headless).cli;
    "the t3 wrapper wraps the module's package" = (internal headless).cli.unwrapped.outPath == headless.othrys.apps.ai.t3code.package.outPath;
    "the t3 wrapper turns telemetry off" = lib.hasInfix "T3CODE_TELEMETRY_ENABLED" (wrapperScript (internal headless).cli);
    "telemetry can be left on" = !(lib.hasInfix "T3CODE_TELEMETRY_ENABLED" (wrapperScript (internal telemetryOn).cli));

    "desktop mode installs the wrapped desktop app" = installed desktop (internal desktop).desktop;
    "desktop mode installs t3 beside it" = installed desktop (internal desktop).cli;
    "the desktop wrapper turns the app's self-update off" = lib.hasInfix "T3CODE_DISABLE_AUTO_UPDATE" (wrapperScript (internal desktop).desktop);
    # The flag holds the wrapper's own output, which the build text names by
    # its placeholder.
    "the desktop wrapper names itself as the link handler's launcher" = lib.hasInfix "T3CODE_DESKTOP_LAUNCHER_PATH ${builtins.placeholder "out"}/bin/t3code-desktop" (wrapperScript (internal desktop).desktop);
    "the desktop wrapper turns telemetry off" = lib.hasInfix "T3CODE_TELEMETRY_ENABLED" (wrapperScript (internal desktop).desktop);
    "headless mode does not install the desktop app" = !(installed headless (internal headless).desktop);

    "headless mode runs the server as a systemd user unit" = (hmOf headless).systemd.user.services ? t3code;
    # Home Manager stores each unit setting as a list.
    "the unit runs the serve script" = (unit headless).Service.ExecStart == ["${(internal headless).serve}"];
    "the unit starts with the user's manager" = (unit headless).Install.WantedBy == ["default.target"];
    "the unit restarts the server whenever it exits" = (unit headless).Service.Restart == "always";
    "the unit's PATH starts with the setuid wrappers and the user's profile" = lib.take 2 pathEntries == ["/run/wrappers/bin" "/etc/profiles/per-user/alice/bin"];
    "headless mode lets the user linger, so the server runs from boot" = headless.users.users.alice.linger;
    "desktop mode leaves lingering alone" = desktop.users.users.alice.linger != true;
    "an account without Home Manager does not linger" = (noHome.users.users.${noHome.othrys.system.user.name}.linger or null) != true;
    "the unit's PATH ends with git" = builtins.match "/nix/store/[a-z0-9]{32}-git-[0-9.]+/bin" (lib.last pathEntries) != null;
    "desktop mode runs no unit" = !((hmOf desktop).systemd.user.services ? t3code);

    "loopback serves on 127.0.0.1 at port 3773" = lib.hasInfix "serve --host 127.0.0.1 --port 3773" (serveText headless);
    "lan serves with --lan" = lib.hasInfix "serve --lan --port 3773" (serveText lan);
    "tailscale reads the tailnet address when the server starts" =
      lib.hasInfix "tailscale ip -4" (serveText tailnet) && lib.hasInfix "serve --host \"$address\" --port 3773" (serveText tailnet);
    "a host's own port reaches the command line" = lib.hasInfix "--port 4000" (serveText lanPort);

    "lan opens the port in the firewall" = builtins.elem 3773 (globalPorts lan);
    "lan opens the host's own port" = builtins.elem 4000 (globalPorts lanPort) && !(builtins.elem 3773 (globalPorts lanPort));
    "tailscale opens the port on Tailscale's interface alone" = builtins.elem 3773 (tailnetPorts tailnet) && !(builtins.elem 3773 (globalPorts tailnet));
    "loopback opens no port" = !(builtins.elem 3773 (globalPorts headless)) && !(builtins.elem 3773 (tailnetPorts headless));

    "headless mode persists ~/.t3 at 0700 and nothing else" = persisted headless == dirs [".t3"];
    "desktop mode also persists the Electron profile at 0700" = persisted desktop == dirs [".t3" ".config/t3code-v2"];
    "the host trusts the cache the package comes from" = headless.othrys.internal.llmAgentsCache && builtins.elem "https://cache.numtide.com" headless.nix.settings.substituters;

    "a headless host with an agent passes every t3code assertion" = !(refusedByT3code headless);
    "a desktop host with a graphical session passes every t3code assertion" = !(refusedByT3code desktop);
    "a host that sets no mode is refused" = rejectedWith "othrys.apps.ai.t3code.mode is unset" unsetMode;
    "a host with neither agent is refused" = rejectedWith "neither othrys.apps.ai.codex.enable nor othrys.apps.ai.claude-code.enable is set" noAgents;
    "desktop mode without a graphical session is refused" = rejectedWith "t3code.mode = \"desktop\" requires a graphical session" desktopNoSession;
    "desktop mode with a listen address is refused" = rejectedWith "listen is \"lan\", which sets where the headless server listens" desktopLan;
    "tailscale without Tailscale is refused" = rejectedWith "binds the host's tailnet address, which needs othrys.services.tailscale.enable" tailnetNoTailscale;

    "a host without the module writes nothing for it" =
      !(off.othrys.internal.homeConfig ? "apps.ai.t3code")
      && !(off.othrys.internal.homeConfig ? "apps.ai.t3code-service")
      && !(off.othrys.internal.persist ? "apps.ai.t3code")
      && !((hmOf off).systemd.user.services ? t3code);
  }
