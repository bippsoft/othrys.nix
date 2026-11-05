# flake/checks/claude-desktop-eval.nix
# CORE. What the claude-desktop module installs, refuses and merges into the
# app's config, read back from evaluated hosts. The MCP servers reach the app
# through an activation step that runs on the host and never at evaluation,
# so the step's script is read here for the servers it carries.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  functioningHost,
  inputs,
  system,
}: let
  package = inputs.llm-agents.packages.${system}.claude-desktop;
  host = extra:
    hostConfig [
      functioningHost
      {
        othrys.desktop.graphical = true;
        othrys.system.nix.allowUnfree = true;
        othrys.apps.ai.claude-desktop.enable = true;
        othrys.apps.ai.mcp.context7.enable = true;
      }
      extra
    ];
  # One local server beside the remote Context7 one.
  localServer = {
    othrys.internal.homeConfig."fixture.mcp" = {
      programs.mcp.servers.local-fixture = {
        command = "fixture-server";
        args = ["--stdio"];
      };
    };
  };
  hmOf = h: h.home-manager.users.${h.othrys.system.user.name};
  withLocal = host localServer;
  remoteOnly = host {};
  step = (hmOf withLocal).home.activation.othrysClaudeDesktopMcp.data;
  installs = h: builtins.any (p: (p.outPath or null) == package.outPath) (hmOf h).home.packages;
  headless = hostConfig [
    functioningHost
    {
      othrys.system.nix.allowUnfree = true;
      othrys.apps.ai.claude-desktop.enable = true;
    }
  ];
  unfreeOff = hostConfig [
    functioningHost
    {
      othrys.desktop.graphical = true;
      othrys.apps.ai.claude-desktop.enable = true;
    }
  ];
  off = hostConfig [functioningHost {othrys.desktop.graphical = true;}];
  swapped = host ({pkgs, ...}: {othrys.apps.ai.claude-desktop.package = pkgs.hello;});
  hasInfix = inputs.nixpkgs.lib.hasInfix;
in
  mkExpectations "othrys-eval-claude-desktop" {
    "the user's profile installs llm-agents' claude-desktop" = installs remoteOnly;
    "a host can set the package" = builtins.any (p: (p.pname or "") == "hello") (hmOf swapped).home.packages && !installs swapped;
    "the activation step writes the local server" = hasInfix "fixture-server" step && hasInfix "mcpServers" step;
    "the activation step leaves out a remote server" = !hasInfix "context7" step;
    "with no local server the app's config is left alone" = !((hmOf remoteOnly).home.activation ? othrysClaudeDesktopMcp);
    "~/.config/Claude is persisted at 0700" =
      remoteOnly.othrys.internal.persist."apps.ai.claude-desktop".user.directories
      == [
        {
          directory = ".config/Claude";
          mode = "0700";
        }
      ];
    "the host trusts the cache the package comes from" = builtins.elem "https://cache.numtide.com" remoteOnly.nix.settings.substituters;
    "a host with no graphical session is refused" = rejectedWith "requires a graphical session" headless;
    "a host that admits no unfree software is refused" = rejectedWith "marks it free so nixpkgs never checks" unfreeOff;
    "a host without the module writes nothing for it" = !(off.othrys.internal.homeConfig ? "apps.ai.claude-desktop") && !(off.othrys.internal.persist ? "apps.ai.claude-desktop");
  }
