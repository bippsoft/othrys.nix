# flake/checks/darwin-eval.nix
# CORE. What the darwin exports write on a nix-darwin host. The account stays
# with macOS unless the host gives a uid, Nix defaults to Lix, the locale
# reaches the environment, a host that names a user and turns nothing on gets
# no account settings at all, the home adapter hands the apps' user
# configuration to Home Manager with the darwin packages and paths, and the
# SSH, Tailscale, mosh, YubiKey, Ollama, T3 Code and Paseo modules write
# what nix-darwin and Home Manager run there and refuse what they cannot
# apply.
# codex and Claude Code reach Home Manager and T3 Code through the
# project-environment launcher, and as themselves with it off.
{
  lib,
  darwinConfig,
  darwinBase,
  darwinHomeModules,
  darwinAppHost,
  darwinManagedBase,
  darwinServiceHosts,
  mkExpectations,
  rejectedWith,
  inputs,
}: let
  account = {
    othrys.system.users = {
      enable = true;
      homeManager.enable = false;
    };
  };

  bare = darwinConfig [darwinBase];
  managed = darwinConfig [darwinBase account];
  known = darwinConfig [
    darwinBase
    account
    {othrys.system.users.uid = 502;}
    {othrys.system.shell.zsh.enable = true;}
  ];
  configured = darwinConfig [
    darwinBase
    account
    {
      othrys.system = {
        nix = {
          enable = true;
          stateVersion = "26.05";
        };
        locale = {
          enable = true;
          timezone = "Europe/Berlin";
          locale = "de_DE.UTF-8";
        };
        git = {
          enable = true;
          name = "Alice";
          email = "alice@example.com";
        };
      };
    }
  ];
  # Zsh with the Nix and clipboard presets left to their defaults, and an
  # editor of the host's choosing.
  shell = darwinConfig [
    darwinBase
    {
      othrys.system.shell.zsh.enable = true;
      othrys.system.defaultEditor = "nvim";
    }
  ];
  zshAliases = shell.othrys.internal.homeConfig."system.shell.zsh".programs.zsh.shellAliases;
  # A nixpkgs instance passed in with allowUnfree off while othrys.system.nix
  # allows it, which the module refuses as it does on NixOS.
  externalPkgs = darwinConfig [
    darwinBase
    {
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
        allowUnfree = true;
      };
      nixpkgs.pkgs = import inputs.nixpkgs {system = "aarch64-darwin";};
    }
  ];
  # Every darwin app on, with Home Manager and the home adapter, read back
  # from the user's Home Manager configuration.
  apps = darwinConfig [darwinBase darwinAppHost];
  home = apps.home-manager.users.alice;
  managedHome = darwinConfig [
    darwinBase
    darwinHomeModules
    {
      othrys.system.users.enable = true;
      # Home Manager's state version comes through the registry from here.
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
    }
  ];
  # The registry still collects entries without the home adapter, which is
  # what the adapter hands to Home Manager on a host that imports it.
  homeEntries = builtins.attrNames configured.othrys.internal.homeConfig;
  withHomeManager = darwinConfig [darwinBase {othrys.system.users.enable = true;}];

  # Each service module on by itself over a managed account, with a
  # change on top for the refusals.
  service = name: extra: darwinConfig [darwinBase darwinManagedBase darwinServiceHosts.${name} extra];
  ssh = service "ssh" {};
  sshHome = ssh.home-manager.users.alice;
  sshdConfig = ssh.environment.etc."ssh/sshd_config.d/100-nix-darwin.conf".text;
  knownHosts = ssh.environment.etc."ssh/ssh_known_hosts".text;
  darwinPkgs = inputs.nixpkgs.legacyPackages.aarch64-darwin;
  sshClientOnly = darwinConfig [darwinBase darwinManagedBase {othrys.services.ssh.enable = true;}];
  onSystemPath = cfg: pkg: builtins.any (p: p.drvPath or null == pkg.drvPath) cfg.environment.systemPackages;
  tailscale = service "tailscale" {};
  mosh = service "mosh" {};
  yubikey = service "yubikey" {};
  gpgAgent = yubikey.home-manager.users.alice.services.gpg-agent;
  ollama = service "ollama" {};
  ollamaHome = ollama.home-manager.users.alice;
  ollamaAgent = ollamaHome.launchd.agents.ollama;
  # An agent bound to every address on another port, and one bound to a
  # single LAN address, for what the user's client is told.
  ollamaWide =
    (service "ollama" {
      othrys.apps.ai.ollama = {
        host = "0.0.0.0";
        port = 11500;
      };
    }).home-manager.users.alice;
  ollamaLan = (service "ollama" {othrys.apps.ai.ollama.host = "10.0.0.5";}).home-manager.users.alice;
  ollamaV6 = (service "ollama" {othrys.apps.ai.ollama.host = "fd00::5";}).home-manager.users.alice;
  ollamaAllV6 = (service "ollama" {othrys.apps.ai.ollama.host = "::";}).home-manager.users.alice;
  # The app host runs T3 Code headless. A second host runs the desktop app
  # with codex alone, which a Mac's graphical session admits.
  t3Agent = home.launchd.agents.t3code;
  t3Serve = apps.othrys.internal.t3code.serve;
  t3Path = lib.splitString ":" t3Agent.config.EnvironmentVariables.PATH;
  t3Desktop = darwinConfig [
    darwinBase
    darwinManagedBase
    {
      othrys.apps.ai = {
        codex.enable = true;
        t3code = {
          enable = true;
          mode = "desktop";
        };
      };
    }
  ];
  t3DesktopHome = t3Desktop.home-manager.users.alice;
  t3DesktopApp = t3Desktop.othrys.internal.t3code.desktop;
  t3DesktopScript = (t3DesktopApp.drvAttrs.buildCommand or "") + (t3DesktopApp.drvAttrs.postBuild or "");
  installedFor = h: pkg: builtins.any (p: (p.outPath or null) == pkg.outPath) h.home.packages;

  # The app host starts both agents through the project-environment
  # launcher, which is on by default. A second host has codex and Claude
  # Code with the launcher off, and a third keeps the launcher while it
  # leaves new worktrees blocked.
  same = a: b: a.outPath == b.outPath;
  drvPaths = map (p: p.drvPath);
  darwinAgents = inputs.llm-agents.packages.aarch64-darwin;
  quietClaude = darwinAgents.claude-code.override {disableTelemetry = true;};
  agents = apps.othrys.internal.agents;
  unwrapped = darwinConfig [
    darwinBase
    darwinManagedBase
    {
      othrys.system.nix.allowUnfree = true;
      othrys.apps.ai = {
        claude-code.enable = true;
        codex.enable = true;
        projectEnvironment.enable = false;
      };
    }
  ];
  unwrappedHome = unwrapped.home-manager.users.alice;
  untrusting = darwinConfig [
    darwinBase
    darwinManagedBase
    {
      othrys.apps.ai = {
        codex.enable = true;
        projectEnvironment.trustWorktrees = false;
      };
    }
  ];
  launcherText = agent: agent.passthru.launcher.drvAttrs.text or "";

  # Paseo with its daemon over the managed account, with codex for the agent
  # it drives. The plugin is a stand-in directory, so no expectation here
  # reads the paseo-direnv input.
  paseoHost = extra:
    darwinConfig [
      darwinBase
      darwinManagedBase
      ({pkgs, ...}: {
        othrys.apps.ai = {
          codex.enable = true;
          paseo = {
            enable = true;
            direnv.package = pkgs.runCommand "paseo-direnv-standin" {} "mkdir -p \"$out\"";
          };
        };
      })
      extra
    ];
  paseoServed = paseoHost {othrys.apps.ai.paseo.service.enable = true;};
  paseoAgent = paseoServed.home-manager.users.alice.launchd.agents.paseo;
  paseoPlain = paseoHost {};
  paseoDesktop = paseoHost {othrys.apps.ai.paseo.desktop.enable = true;};
in
  mkExpectations "othrys-eval-darwin" {
    "a host with only a user named sets no primary user" = bare.system.primaryUser == null;
    "a host with only a user named writes no account" = !(bare.users.users ? alice);
    "a Mac runs a graphical session by default" = bare.othrys.desktop.graphical;
    "EDITOR defaults to vim" = bare.environment.variables.EDITOR == "vim";

    "the account makes alice the primary user" = managed.system.primaryUser == "alice";
    "the account's home is under /Users" = managed.users.users.alice.home == "/Users/alice";
    "an account without a uid stays out of knownUsers" = !(builtins.elem "alice" managed.users.knownUsers);
    "an account without a uid gets no shell from othrys" = managed.users.users.alice.shell == null;

    "a uid hands the account to nix-darwin" = builtins.elem "alice" known.users.knownUsers && known.users.users.alice.uid == 502;
    "a known account takes the zsh login shell" = (known.users.users.alice.shell.pname or null) == "zsh";
    "zsh is enabled for the login shell" = known.programs.zsh.enable;

    "Nix defaults to Lix" = lib.getName configured.nix.package == "lix";
    "nix-darwin keeps managing Nix" = configured.nix.enable;
    "flakes are enabled" = builtins.elem "flakes" configured.nix.settings.experimental-features;
    "the store is optimised by the scheduled job, not on every write" = configured.nix.optimise.automatic && !(configured.nix.settings.auto-optimise-store or false);
    "nixpkgs is pinned in the registry" = configured.nix.registry.nixpkgs.flake.outPath == inputs.nixpkgs.outPath;
    "the timezone is set" = configured.time.timeZone == "Europe/Berlin";
    "the locale reaches LANG" = configured.environment.variables.LANG == "de_DE.UTF-8";
    # The nix entry carries the Home Manager state version and is withheld
    # while Home Manager manages no account.
    "git hands its user configuration to the registry" = builtins.elem "system.git" homeEntries;
    "nix withholds its entry from an account Home Manager does not manage" = !(builtins.elem "system.nix" homeEntries);

    "a known account is visible and gets a home directory" = !known.users.users.alice.isHidden && known.users.users.alice.createHome;
    "the default bash login shell is the interactive build" = (darwinConfig [darwinBase account {othrys.system.users.uid = 502;}]).users.users.alice.shell.pname == "bash-interactive";
    "the othrys pin replaces nix-darwin's own registry and NIX_PATH entries" = !configured.nixpkgs.flake.setFlakeRegistry && !configured.nixpkgs.flake.setNixPath;
    "git is installed system-wide" = builtins.any (p: lib.getName p == "git") configured.environment.systemPackages;
    "EDITOR and VISUAL follow defaultEditor" = shell.environment.variables.EDITOR == "nvim" && shell.environment.variables.VISUAL == "nvim";
    "the rebuild alias runs darwin-rebuild" = zshAliases.rebuild == "sudo darwin-rebuild switch --flake .";
    "there is no rebuild-test alias on darwin" = !(zshAliases ? rebuild-test);
    "the clipboard preset is off on a Mac" = !shell.othrys.system.shell.zsh.aliasPresets.clipboard;
    "an external nixpkgs that disagrees on allowUnfree is refused" = rejectedWith "nixpkgs.pkgs is defined externally" externalPkgs;
    "the home adapter gives Home Manager the account's home" = home.home.homeDirectory == "/Users/alice";
    "the home adapter hands the user the registry" = home.programs.nixvim.enable && home.programs.gh.enable;
    "the essential user tools reach the darwin user" = builtins.any (p: lib.getName p == "just") home.home.packages;
    "an account with Home Manager and the adapter is accepted" = !(rejectedWith "is not imported" managedHome);
    "Ghostty takes the darwin build" = lib.getName home.programs.ghostty.package == "ghostty-bin";
    "kitty's control socket sits in the per-user TMPDIR" = lib.hasPrefix "unix:\${TMPDIR}/" home.programs.kitty.settings.listen_on;
    "VSCodium finds nixvim under the darwin key" = home.programs.vscodium.profiles.default.userSettings ? "vscode-neovim.neovimExecutablePaths.darwin";
    "the assistants are not told they run on NixOS" = !apps.othrys.apps.ai.context.nixos.enable && !(lib.hasInfix "NixOS" apps.othrys.apps.ai.context.text);
    "tmux reaches the darwin user with tmux-256color" = home.programs.tmux.enable && home.programs.tmux.terminal == "tmux-256color";
    "tmux brings its terminfo entry to a Mac" = builtins.any (p: lib.hasSuffix "-terminfo" (p.name or "")) home.home.packages;
    "yazi pulls no Wayland clipboard on a Mac" = !(builtins.any (p: lib.getName p == "wl-clipboard") home.home.packages);
    "an account with Home Manager on and no home adapter is refused" = rejectedWith "darwinModules.home is not imported" withHomeManager;

    "the SSH module turns Remote Login on" = ssh.services.openssh.enable == true;
    "the hardened sshd settings reach the darwin sshd" = lib.hasInfix "PasswordAuthentication no" sshdConfig && lib.hasInfix "PermitRootLogin no" sshdConfig && lib.hasInfix "AllowAgentForwarding no" sshdConfig;
    "the darwin sshd is offered no key exchange older releases refuse" = lib.hasInfix "KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256" sshdConfig && !(lib.hasInfix "mlkem" sshdConfig);
    "an SSH server on a Mac carries the Ghostty and kitty terminfo" = onSystemPath ssh darwinPkgs.ghostty-bin.terminfo && onSystemPath ssh darwinPkgs.kitty.terminfo && builtins.elem "/share/terminfo" ssh.environment.pathsToLink;
    "the SSH client alone carries neither terminfo" = !(onSystemPath sshClientOnly darwinPkgs.ghostty-bin.terminfo) && !(onSystemPath sshClientOnly darwinPkgs.kitty.terminfo);
    "the forge keys and the host's own known host are trusted" = lib.hasInfix "github.com ssh-ed25519" knownHosts && lib.hasInfix "nas.example.com ssh-ed25519" knownHosts;
    "the SSH client configuration reaches the darwin user" = sshHome.programs.ssh.enable && sshHome.programs.ssh.settings."*".data.StrictHostKeyChecking == "ask";
    "a darwin SSH port other than 22 is refused" = rejectedWith "listens on port 22 alone" (service "ssh" {othrys.services.ssh.server.ports = [2222];});
    "the SSH client alone leaves Remote Login to macOS" = sshClientOnly.services.openssh.enable == null;

    "the Tailscale module runs tailscaled" = tailscale.services.tailscale.enable;
    "a Tailscale host with the defaults is accepted" = !(rejectedWith "nix-darwin runs no" tailscale);
    "a darwin Tailscale setting nothing applies is refused" = rejectedWith "sets acceptRoutes, operator on a darwin host" (service "tailscale" {
      othrys.services.tailscale = {
        acceptRoutes = true;
        operator = "alice";
      };
    });

    "the other darwin Tailscale settings nothing applies are refused" = rejectedWith "sets authKeyFile, baseURL, ssh, acceptDns, ephemeral on a darwin host" (service "tailscale" {
      othrys.services.tailscale = {
        authKeyFile = "/run/secrets/tailscale";
        baseURL = "https://headscale.example.com";
        ssh = true;
        acceptDns = false;
        ephemeral = true;
      };
    });

    "the mosh module puts mosh on the system path" = builtins.any (p: lib.getName p == "mosh") mosh.environment.systemPackages;
    "a host without the mosh module has no mosh on the system path" = !(builtins.any (p: lib.getName p == "mosh") tailscale.environment.systemPackages);

    "the gpg-agent runs as the user's launchd agent" = gpgAgent.enable && gpgAgent.enableSshSupport && yubikey.home-manager.users.alice.launchd.agents.gpg-agent.enable;
    "the PIN prompt is pinentry-mac" = lib.getName gpgAgent.pinentry.package == "pinentry-mac";
    "a Mac with the graphical flag off prompts on the terminal" = lib.getName (service "yubikey" {othrys.desktop.graphical = false;}).home-manager.users.alice.services.gpg-agent.pinentry.package == "pinentry-curses";
    "the hardened gpg.conf reaches the darwin user" = yubikey.home-manager.users.alice.programs.gpg.settings.throw-keyids;
    "the YubiKey tools are installed and pam_u2f is not" = builtins.any (p: lib.getName p == "yubikey-manager") yubikey.environment.systemPackages && !(builtins.any (p: lib.getName p == "pam_u2f") yubikey.environment.systemPackages);
    "a darwin U2F mapping is refused" = rejectedWith "writes no pam_u2f line on nix-darwin" (service "yubikey" {
      othrys.services.security.yubikey.u2fMappings.alice = ["handle,key,es256,+presence"];
    });
    "Touch ID for sudo stays off" = !yubikey.security.pam.services.sudo_local.touchIdAuth;

    "Ollama defaults to the CPU build on a Mac" = ollama.othrys.apps.ai.ollama.acceleration == "cpu";
    "Ollama runs as the user's launchd agent" = ollamaAgent.enable && builtins.elem "serve" ollamaAgent.config.ProgramArguments;
    "the Ollama agent listens on 127.0.0.1:11434" = ollamaAgent.config.EnvironmentVariables.OLLAMA_HOST == "127.0.0.1:11434";
    "the user's OLLAMA_HOST points at the agent" = ollamaHome.home.sessionVariables.OLLAMA_HOST == "http://127.0.0.1:11434";
    "the Ollama host and port reach the agent" = ollamaWide.launchd.agents.ollama.config.EnvironmentVariables.OLLAMA_HOST == "0.0.0.0:11500";
    "an agent on every address is reached on loopback" = ollamaWide.home.sessionVariables.OLLAMA_HOST == "http://127.0.0.1:11500";
    "an agent on one address is reached on that address" = ollamaLan.home.sessionVariables.OLLAMA_HOST == "http://10.0.0.5:11434";
    "an IPv6 address reaches the agent in brackets" = ollamaV6.launchd.agents.ollama.config.EnvironmentVariables.OLLAMA_HOST == "[fd00::5]:11434" && ollamaV6.home.sessionVariables.OLLAMA_HOST == "http://[fd00::5]:11434";
    "an agent on every IPv6 address is reached on IPv6 loopback" = ollamaAllV6.launchd.agents.ollama.config.EnvironmentVariables.OLLAMA_HOST == "[::]:11434" && ollamaAllV6.home.sessionVariables.OLLAMA_HOST == "http://[::1]:11434";
    "the Ollama package is the CPU build" = ollamaHome.services.ollama.package.drvPath == inputs.nixpkgs.legacyPackages.aarch64-darwin.ollama-cpu.drvPath;
    "a GPU Ollama build on darwin is refused" = rejectedWith "builds that package for Linux alone" (service "ollama" {othrys.apps.ai.ollama.acceleration = "vulkan";});
    "Ollama models to pull on darwin are refused" = rejectedWith "pulls no models" (service "ollama" {othrys.apps.ai.ollama.loadModels = ["llama3.1"];});

    "T3 Code runs headless as the user's launchd agent" = t3Agent.enable;
    "the T3 Code agent runs the serve script and nothing else" = t3Agent.config.ProgramArguments == ["${t3Serve}"];
    "launchd starts the T3 Code agent again whenever it exits" = t3Agent.config.KeepAlive == true && t3Agent.config.RunAtLoad == true;
    "the T3 Code agent's PATH holds the user's profile and /usr/bin" = builtins.head t3Path == "/etc/profiles/per-user/alice/bin" && builtins.elem "/usr/bin" t3Path;
    # git comes ahead of /usr/bin, whose git is a stub without the Command
    # Line Tools.
    "the T3 Code agent's PATH holds git ahead of /usr/bin and /bin" = let
      tail = lib.drop 2 t3Path;
    in
      builtins.length tail
      == 3
      && builtins.match "/nix/store/[a-z0-9]{32}-git-[0-9.]+/bin" (builtins.head tail) != null
      && lib.drop 1 tail == ["/usr/bin" "/bin"];
    "headless T3 Code on darwin installs t3 and no desktop app" = installedFor home apps.othrys.internal.t3code.cli && !(installedFor home apps.othrys.internal.t3code.desktop);
    "desktop T3 Code on darwin installs the desktop app" = installedFor t3DesktopHome t3DesktopApp;
    "desktop T3 Code on darwin runs no launchd agent" = !(t3DesktopHome.launchd.agents ? t3code);
    "the darwin desktop wrapper points the app bundle at itself" = lib.hasInfix ''ln -s "$out/bin/t3code-desktop" "$macos/T3 Code (Beta)"'' t3DesktopScript && !(lib.hasInfix "T3CODE_DESKTOP_LAUNCHER_PATH" t3DesktopScript);
    "the darwin desktop wrapper fails a build with no app bundle" = lib.hasInfix ''[ ! -L "$macos/T3 Code (Beta)" ]'' t3DesktopScript;
    "the darwin desktop wrapper turns the app's self-update off" = lib.hasInfix "T3CODE_DISABLE_AUTO_UPDATE" t3DesktopScript;

    "the Paseo service runs as the user's launchd agent" = paseoAgent.enable;
    "the Paseo agent runs the serve script and nothing else" = paseoAgent.config.ProgramArguments == ["${paseoServed.othrys.internal.paseo.serve}"];
    "launchd starts the Paseo agent at login and again whenever it exits" = paseoAgent.config.KeepAlive == true && paseoAgent.config.RunAtLoad == true;
    "launchd starts the Paseo agent no sooner than ten seconds apart" = paseoAgent.config.ThrottleInterval == 10;
    "the Paseo agent's PATH holds the user's profile, git and the system tools" =
      paseoAgent.config.EnvironmentVariables.PATH
      == "/etc/profiles/per-user/alice/bin:/run/current-system/sw/bin:${darwinPkgs.git}/bin:/usr/bin:/bin";
    "the Paseo agent logs to ~/Library/Logs/paseo.log" =
      paseoAgent.config.StandardOutPath
      == "/Users/alice/Library/Logs/paseo.log"
      && paseoAgent.config.StandardErrorPath == "/Users/alice/Library/Logs/paseo.log";
    "a Mac with codex and the Paseo service passes every paseo assertion" = !(builtins.any (a: !a.assertion && lib.hasInfix "othrys.apps.ai.paseo" a.message) paseoServed.assertions);
    "Paseo without the service runs no launchd agent on a Mac" = !(paseoPlain.home-manager.users.alice.launchd.agents ? paseo);
    "the Paseo desktop app on a Mac is refused" = rejectedWith "othrys.apps.ai.paseo.desktop.enable is set on darwin" paseoDesktop;

    "the launcher on a Mac wraps llm-agents' codex" = same agents.codex.passthru.unwrapped darwinAgents.codex && !(same agents.codex darwinAgents.codex);
    "the launcher on a Mac wraps llm-agents' claude-code built without telemetry" = same agents.claude-code.passthru.unwrapped quietClaude && !(same agents.claude-code quietClaude);
    "the launchers on a Mac keep codex and claude as their programs" = agents.codex.meta.mainProgram == "codex" && agents.claude-code.meta.mainProgram == "claude";
    "the launcher fails a build with no codex program" = lib.hasInfix ''[ ! -e "$out/bin/codex" ]'' ((agents.codex.drvAttrs.buildCommand or "") + (agents.codex.drvAttrs.postBuild or ""));
    "the launcher allows a new worktree's identical .envrc by default" = lib.hasInfix ''"$direnv" allow'' (launcherText agents.codex);
    "with trustWorktrees off the launcher never runs direnv allow" =
      lib.hasInfix "direnv\" exec" (launcherText untrusting.othrys.internal.agents.codex)
      && !(lib.hasInfix ''"$direnv" allow'' (launcherText untrusting.othrys.internal.agents.codex));
    "Home Manager on a Mac installs the launchers" = same home.programs.codex.package agents.codex && same home.programs.claude-code.package agents.claude-code;
    "T3 Code on a Mac is handed the launchers, codex first" = drvPaths (apps.othrys.apps.ai.t3code.package.providerPackages or []) == drvPaths [agents.codex agents.claude-code];
    "with the launcher off a Mac installs the agents themselves" =
      same unwrappedHome.programs.codex.package darwinAgents.codex
      && same unwrappedHome.programs.claude-code.package quietClaude
      && same unwrapped.othrys.internal.agents.codex darwinAgents.codex
      && same unwrapped.othrys.internal.agents.claude-code quietClaude;
  }
