# flake/checks/paseo-eval.nix
# CORE. What the paseo module installs, runs, opens and persists, read back
# from evaluated NixOS hosts. The daemon's listen address, the relay switch,
# the password, the agents on its PATH and the direnv plugin's config.json
# entry are lines of the start scripts, and the port is a firewall list.
# None of them fails evaluation when it is wrong. The plugin is a stand-in
# directory wherever its path is compared, so no expectation but one reads
# the paseo-direnv input, and that one compares the option's default with it.
{
  lib,
  hostConfig,
  hostEval,
  mkExpectations,
  rejectedWith,
  functioningHost,
  accountNoHomeManager,
  inputs,
  system,
}: let
  llmAgents = inputs.llm-agents.packages.${system};
  nixpkgs = inputs.nixpkgs.legacyPackages.${system};
  codexOn = {othrys.apps.ai.codex.enable = true;};
  # A plugin directory that stands in for the paseo-direnv input.
  standInPlugin = {pkgs, ...}: {
    othrys.apps.ai.paseo.direnv.package = pkgs.runCommand "paseo-direnv-standin" {} ''
      mkdir -p "$out"
      echo '{"name": "paseo-direnv"}' > "$out/package.json"
    '';
  };
  hostModules = extras: [functioningHost codexOn standInPlugin] ++ extras;
  host = extras: hostConfig (hostModules extras);
  paseo = settings: {othrys.apps.ai.paseo = {enable = true;} // settings;};
  served = settings: paseo ({service.enable = true;} // settings);

  plainEval = hostEval (hostModules [(paseo {})]);
  plain = plainEval.config;
  offEval = hostEval (hostModules [{othrys.desktop.graphical = true;}]);
  off = offEval.config;
  desktop = host [
    {othrys.desktop.graphical = true;}
    (paseo {desktop.enable = true;})
  ];
  service = host [(served {})];
  # A desktop package of the host's own, a directory the option must install.
  ownDesktop = nixpkgs.runCommand "paseo-desktop-standin" {} "mkdir -p \"$out\"";
  desktopOwn = host [
    {othrys.desktop.graphical = true;}
    (paseo {
      desktop.enable = true;
      desktop.package = ownDesktop;
    })
  ];
  # An account othrys creates without Home Manager, where the unit never
  # reaches the user and lingering would start a manager with nothing to run.
  noHome = hostConfig [
    accountNoHomeManager
    codexOn
    standInPlugin
    (served {})
  ];
  lan = host [(served {listen = "lan";})];
  lanPort = host [
    (served {
      listen = "lan";
      port = 7000;
    })
  ];
  lanPassword = host [
    (served {
      listen = "lan";
      passwordFile = "/run/secrets/paseo-password";
    })
  ];
  tailnet = host [
    {othrys.services.tailscale.enable = true;}
    (served {listen = "tailscale";})
  ];
  relay = host [(served {relay.enable = true;})];
  proxied = host [
    (served {
      webUi.enable = true;
      hostnames = ["paseo.example.com" "code.example.com"];
    })
  ];
  untrusting = host [
    {othrys.apps.ai.projectEnvironment.trustWorktrees = false;}
    (served {})
  ];
  noEnvironment = host [
    {othrys.apps.ai.projectEnvironment.enable = false;}
    (served {})
  ];
  direnvOff = host [(served {direnv.enable = false;})];
  # The plugin's default package, with no stand-in.
  defaultPlugin = hostConfig [functioningHost codexOn (served {})];

  noAgents = hostConfig [functioningHost (paseo {})];
  desktopNoSession = host [(paseo {desktop.enable = true;})];
  tailnetNoTailscale = host [(served {listen = "tailscale";})];
  lanNoService = host [(paseo {listen = "lan";})];
  relayNoService = host [(paseo {relay.enable = true;})];
  passwordNoService = host [(paseo {passwordFile = "/run/secrets/paseo-password";})];
  direnvNoService = host [(paseo {direnv.enable = true;})];
  webUiNoService = host [(paseo {webUi.enable = true;})];
  hostnamesNoService = host [(paseo {hostnames = ["paseo.example.com"];})];

  user = h: h.othrys.system.user.name;
  hmOf = h: h.home-manager.users.${user h};
  same = a: b: a.outPath == b.outPath;
  installed = h: pkg: builtins.any (p: (p.outPath or null) == pkg.outPath) (hmOf h).home.packages;
  serve = h: h.othrys.internal.paseo.serve;
  text = h: (serve h).text;
  # A regex may not refer to a store path, and lib.hasInfix builds one from
  # the needle, so both sides are compared without their context.
  noContext = builtins.unsafeDiscardStringContext;
  contains = needle: haystack: lib.hasInfix (noContext needle) (noContext haystack);
  has = needle: h: contains needle (text h);
  # The script that edits config.json, which the serve script runs.
  pluginConfig = h: h.othrys.internal.paseo.pluginConfig;
  hasConfig = needle: h: contains needle (pluginConfig h).text;
  activation = h: (hmOf h).home.activation;
  unit = h: (hmOf h).systemd.user.services.paseo;
  plugin = h: h.othrys.apps.ai.paseo.direnv.package;

  # The entries of the PATH the script exports, ahead of the inherited one.
  lines = h: lib.splitString "\n" (text h);
  pathEntries = h: let
    line = lib.findFirst (lib.hasPrefix "export PATH=") "" (lines h);
  in
    lib.splitString ":" (lib.removePrefix "export PATH=" line);
  # makeBinPath takes each package's bin output.
  binOf = pkg: "${lib.getBin pkg}/bin";
  onPath = name: h: builtins.any (e: builtins.match "/nix/store/[a-z0-9]{32}-${name}-[0-9.]+/bin" e != null) (pathEntries h);

  tailnetPorts = h: h.networking.firewall.interfaces.${h.services.tailscale.interfaceName}.allowedTCPPorts or [];
  globalPorts = h: h.networking.firewall.allowedTCPPorts;
  warned = h: builtins.any (lib.hasInfix "othrys.apps.ai.paseo.passwordFile is unset") h.warnings;

  dirs = list:
    map (directory: {
      inherit directory;
      mode = "0700";
    })
    list;
  persisted = h: h.othrys.internal.persist."apps.ai.paseo".user.directories;
  refusedByPaseo = h: builtins.any (a: !a.assertion && lib.hasInfix "othrys.apps.ai.paseo" a.message) h.assertions;
  # Whether paseo.nix itself sets the cache flag, which codex sets as well.
  setsCache = evaluation: builtins.any (d: lib.hasSuffix "/modules/apps/cli/ai/paseo.nix" (toString d.file)) evaluation.options.othrys.internal.llmAgentsCache.definitionsWithLocations;
in
  mkExpectations "othrys-eval-paseo" {
    "the user's profile installs the llm-agents paseo" = installed plain llmAgents.paseo;
    "without the desktop option the desktop app is not installed" = !(installed plain llmAgents.paseo-desktop);
    "the desktop option installs the llm-agents desktop app beside paseo" = installed desktop llmAgents.paseo-desktop && installed desktop llmAgents.paseo;
    "paseo persists ~/.paseo at 0700 and nothing else" = persisted plain == dirs [".paseo"];
    "the desktop app also persists its Electron profile at 0700" = persisted desktop == dirs [".paseo" ".config/Paseo"];
    "paseo itself marks the host as trusting the llm-agents cache" = plain.othrys.internal.llmAgentsCache && setsCache plainEval;
    "a host without paseo leaves the cache flag to other modules" = !(setsCache offEval);

    "the service runs the daemon as a systemd user unit" = (hmOf service).systemd.user.services ? paseo;
    # Home Manager stores each unit setting as a list.
    "the unit runs the serve script" = (unit service).Service.ExecStart == ["${serve service}"];
    "the unit restarts the daemon whenever it exits" = (unit service).Service.Restart == "always";
    "the unit waits ten seconds between restarts and never gives up" = (unit service).Service.RestartSec == 10 && (unit service).Unit.StartLimitIntervalSec == 0;
    "the unit's PATH holds the setuid wrappers, the user's profile and git" =
      (unit service).Service.Environment
      == ["PATH=/run/wrappers/bin:/etc/profiles/per-user/${user service}/bin:/run/current-system/sw/bin:${nixpkgs.git}/bin"];
    "desktop.package is the desktop app installed" = installed desktopOwn ownDesktop && !(installed desktopOwn llmAgents.paseo-desktop);
    "the unit starts with the user's manager" = (unit service).Install.WantedBy == ["default.target"];
    "the service lets the user linger, so the daemon runs from boot" = service.users.users.alice.linger;
    "an account without Home Manager does not linger" = (noHome.users.users.${user noHome}.linger or null) != true;
    "without the service no unit is written" = !((hmOf plain).systemd.user.services ? paseo);
    "without the service the user does not linger" = plain.users.users.alice.linger != true;

    "loopback listens on 127.0.0.1 at port 6767" = has "export PASEO_LISTEN=127.0.0.1:6767\n" service;
    "lan listens on every address" = has "export PASEO_LISTEN=0.0.0.0:6767\n" lan;
    "a host's own port reaches the listen address" = has "export PASEO_LISTEN=0.0.0.0:7000\n" lanPort;
    "tailscale reads the tailnet address when the daemon starts" =
      has "\"$tailscale\" ip -4" tailnet
      && builtins.any (l: builtins.match "tailscale=/nix/store/[a-z0-9]{32}-tailscale-[^/]*/bin/tailscale" l != null) (lines tailnet)
      && has "export PASEO_LISTEN=\"$address:6767\"" tailnet;
    "tailscale admits the host's MagicDNS names" = has "hostnames=\"\${hostnames:+$hostnames,}$name,\${name%%.*}\"" tailnet && has "export PASEO_HOSTNAMES=\"$hostnames\"" tailnet;
    "the web UI is off by default and the setting is always written" = has "export PASEO_WEB_UI_ENABLED=false\n" service;
    "webUi.enable turns the web UI on" = has "export PASEO_WEB_UI_ENABLED=true\n" proxied;
    "no hostname is listed by default" = has "hostnames=''\n" service;
    "hostnames lists each name, comma separated" = has "hostnames=paseo.example.com,code.example.com\n" proxied;
    "loopback reads no tailnet address" = !(has "tailscale" service);

    "lan opens the port in the firewall" = builtins.elem 6767 (globalPorts lan);
    "lan opens the host's own port" = builtins.elem 7000 (globalPorts lanPort) && !(builtins.elem 6767 (globalPorts lanPort));
    "tailscale opens the port on Tailscale's interface alone" = builtins.elem 6767 (tailnetPorts tailnet) && !(builtins.elem 6767 (globalPorts tailnet));
    "loopback opens no port" = !(builtins.elem 6767 (globalPorts service)) && !(builtins.elem 6767 (tailnetPorts service));

    "the hosted relay is off by default" = has "export PASEO_RELAY_ENABLED=false\n" service;
    "relay.enable turns the hosted relay on" = has "export PASEO_RELAY_ENABLED=true\n" relay && !(has "PASEO_RELAY_ENABLED=false" relay);
    "the password file is read when the daemon starts" = has "/run/secrets/paseo-password" lanPassword && has "export PASEO_PASSWORD\n" lanPassword;
    "without a password file no password is exported" = !(has "PASEO_PASSWORD" lan) && !(has "PASEO_PASSWORD" service);
    "the script runs the llm-agents paseo-server" = has "exec ${llmAgents.paseo}/bin/paseo-server" service;
    "the script keeps the daemon's files under ~/.paseo" = has "export PASEO_HOME=\"$HOME/.paseo\"\n" service;
    "the serve script runs the config.json script" = has "${pluginConfig service}\n" service;
    "the config.json script creates files private to the user" = hasConfig "umask 077\n" service;
    "the umask stays out of the daemon and its agents" = !(has "umask" service);

    "the daemon's PATH starts with the codex launcher" = builtins.head (pathEntries service) == binOf service.othrys.internal.agents.codex;
    "the daemon's PATH does not hold the bare llm-agents codex" =
      !(builtins.elem (binOf llmAgents.codex) (pathEntries service))
      && !(same service.othrys.internal.agents.codex llmAgents.codex);
    "a host with codex alone puts three entries and no claude-code ahead of the inherited PATH" =
      !(builtins.any (lib.hasInfix "claude") (pathEntries service))
      && builtins.length (pathEntries service) == 4
      && lib.last (pathEntries service) == "$PATH";
    "with the launcher off the daemon's PATH starts with the bare codex" = builtins.head (pathEntries noEnvironment) == binOf noEnvironment.othrys.apps.ai.codex.package;

    "the direnv plugin is on by default with the service" = service.othrys.apps.ai.paseo.direnv.enable;
    "the direnv plugin is off by default without the service" = !plain.othrys.apps.ai.paseo.direnv.enable;
    "the direnv plugin is off by default with the project environment off" = !noEnvironment.othrys.apps.ai.paseo.direnv.enable;
    "the default plugin is the paseo-direnv input's default package" = same (plugin defaultPlugin) inputs.paseo-direnv.packages.${system}.default;
    "the script points the plugin entry at the plugin's store path" =
      builtins.match "/nix/store/[a-z0-9]{32}-paseo-direnv-standin" "${plugin service}"
      != null
      && hasConfig "--arg path ${plugin service} " service;
    "the script turns plugins on and enables the plugin entry" = hasConfig ".pluginsEnabled = true | .plugins[\"paseo-direnv\"] = {source: \"directory\", path: $path, enabled: true}" service;
    "the plugin trusts identical worktree .envrc files by default" = has "export PASEO_DIRENV_TRUST_WORKTREES=1\n" service;
    "with trustWorktrees off the plugin trusts no worktree .envrc" = has "export PASEO_DIRENV_TRUST_WORKTREES=0\n" untrusting;
    "with the plugin on direnv and git are on the daemon's PATH" = onPath "direnv" service && onPath "git" service;
    "with the plugin off the script removes the plugin entry" = hasConfig "del(.plugins[\"paseo-direnv\"])" direnvOff;
    "with the plugin off the script names no plugin path" = !(hasConfig "paseo-direnv-standin" direnvOff) && !(hasConfig "--arg path" direnvOff);
    "with the plugin off each switch removes the plugin entry" = activation direnvOff ? othrysPaseoDirenv && contains "${pluginConfig direnvOff}" (activation direnvOff).othrysPaseoDirenv.data;
    "without the service the switch removes the plugin entry too" = activation plain ? othrysPaseoDirenv;
    "with the plugin on the switch leaves config.json alone" = !(activation service ? othrysPaseoDirenv);
    "with the plugin off nothing sets worktree trust" = !(has "PASEO_DIRENV_TRUST_WORKTREES" direnvOff);
    "with the plugin off direnv is not on the daemon's PATH" = !(onPath "direnv" direnvOff);
    "with the project environment off the script removes the plugin entry" = hasConfig "del(.plugins[\"paseo-direnv\"])" noEnvironment && !(has "PASEO_DIRENV_TRUST_WORKTREES" noEnvironment);

    "a host with codex and the service passes every paseo assertion" = !(refusedByPaseo service);
    "a host with a password on lan passes every paseo assertion" = !(refusedByPaseo lanPassword);
    "a desktop host with a graphical session passes every paseo assertion" = !(refusedByPaseo desktop);
    "a tailscale host with Tailscale passes every paseo assertion" = !(refusedByPaseo tailnet);
    "a host with neither agent is refused" = rejectedWith "neither othrys.apps.ai.codex.enable nor othrys.apps.ai.claude-code.enable is set" noAgents;
    "the desktop app without a graphical session is refused" = rejectedWith "othrys.apps.ai.paseo.desktop.enable requires a graphical session" desktopNoSession;
    "tailscale without Tailscale is refused" = rejectedWith "binds the host's tailnet address, which needs othrys.services.tailscale.enable" tailnetNoTailscale;
    "lan without the service is refused" = rejectedWith "othrys.apps.ai.paseo.service.enable is unset" lanNoService;
    "the relay without the service is refused" = rejectedWith "othrys.apps.ai.paseo.service.enable is unset" relayNoService;
    "a password file without the service is refused" = rejectedWith "othrys.apps.ai.paseo.service.enable is unset" passwordNoService;
    "the direnv plugin without the service is refused" = rejectedWith "othrys.apps.ai.paseo.service.enable is unset" direnvNoService;
    "the web UI without the service is refused" = rejectedWith "othrys.apps.ai.paseo.service.enable is unset" webUiNoService;
    "hostnames without the service are refused" = rejectedWith "othrys.apps.ai.paseo.service.enable is unset" hostnamesNoService;
    "a proxied host with the service passes every paseo assertion" = !(refusedByPaseo proxied);
    "paseo without the service on loopback is not refused for it" = !(rejectedWith "othrys.apps.ai.paseo.service.enable is unset" plain);

    "lan with the service and no password file warns" = warned lan;
    "lan with a password file does not warn" = !(warned lanPassword);
    "loopback does not warn" = !(warned service);

    "a host without the module writes nothing for it" =
      !(off.othrys.internal.homeConfig ? "apps.ai.paseo")
      && !(off.othrys.internal.homeConfig ? "apps.ai.paseo-service")
      && !(off.othrys.internal.persist ? "apps.ai.paseo")
      && !((hmOf off).systemd.user.services ? paseo)
      && !(warned off);
  }
