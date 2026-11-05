# flake/checks/orca-eval.nix
# CORE. What the orca module installs, persists and opens, read back from
# evaluated hosts. The telemetry switch is an environment variable set by a
# wrapper, and the tailnet port is a firewall rule, and neither fails
# evaluation when it is missing.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  functioningHost,
  inputs,
  system,
}: let
  base = inputs.llm-agents.packages.${system}.orca;
  host = extra:
    hostConfig [
      functioningHost
      {
        othrys.desktop.graphical = true;
        othrys.apps.ai.orca.enable = true;
      }
      extra
    ];
  hmOf = h: h.home-manager.users.${h.othrys.system.user.name};
  lib = inputs.nixpkgs.lib;
  installed = h: lib.findFirst (p: lib.hasPrefix "orca-" (p.name or "")) {outPath = null;} (hmOf h).home.packages;
  plain = host {};
  telemetryOn = host {othrys.apps.ai.orca.disableTelemetry = false;};
  paired = host {
    othrys.services.tailscale.enable = true;
    othrys.apps.ai.orca.tailscale.enable = true;
  };
  noTailnet = host {othrys.apps.ai.orca.tailscale.enable = true;};
  otherPort = host {
    othrys.services.tailscale.enable = true;
    othrys.apps.ai.orca.tailscale = {
      enable = true;
      port = 7000;
    };
  };
  swapped = host ({pkgs, ...}: {othrys.apps.ai.orca.package = pkgs.hello;});
  headless = hostConfig [functioningHost {othrys.apps.ai.orca.enable = true;}];
  off = hostConfig [functioningHost {othrys.desktop.graphical = true;}];
  tailnetPorts = h: h.networking.firewall.interfaces.tailscale0.allowedTCPPorts or [];
in
  mkExpectations "othrys-eval-orca" {
    "the user's profile installs a wrapper, not the bare package" = (installed plain).outPath != null && (installed plain).outPath != base.outPath;
    "the wrapper turns telemetry off" = lib.hasInfix "--set-default ORCA_TELEMETRY_DISABLED 1" (((installed plain).drvAttrs.buildCommand or "") + ((installed plain).drvAttrs.postBuild or ""));
    "the wrapper wraps llm-agents' orca" = (installed plain).unwrapped.outPath == base.outPath;
    "a host can set the package, which is wrapped in turn" = (installed swapped).unwrapped.pname == "hello";
    "telemetry can be left on, with the package as given" = (installed telemetryOn).outPath == base.outPath;
    "the profile, key files and worktrees are persisted at 0700" =
      plain.othrys.internal.persist."apps.ai.orca".user.directories
      == [
        {
          directory = ".config/orca";
          mode = "0700";
        }
        {
          directory = ".orca";
          mode = "0700";
        }
        {
          directory = "orca/workspaces";
          mode = "0700";
        }
      ];
    "the host trusts the cache the package comes from" = builtins.elem "https://cache.numtide.com" plain.nix.settings.substituters;
    "the runtime port stays closed by default" = !builtins.elem 6768 (tailnetPorts plain) && !builtins.elem 6768 plain.networking.firewall.allowedTCPPorts;
    "tailnet access opens the port on Tailscale's interface alone" = builtins.elem 6768 (tailnetPorts paired) && !builtins.elem 6768 paired.networking.firewall.allowedTCPPorts;
    "tailnet access opens the port the host sets" = builtins.elem 7000 (tailnetPorts otherPort) && !builtins.elem 6768 (tailnetPorts otherPort);
    "tailnet access without Tailscale is refused" = rejectedWith "needs othrys.services.tailscale.enable" noTailnet;
    "a host with no graphical session is refused" = rejectedWith "requires a graphical session" headless;
    "a host without the module writes nothing for it" = !(off.othrys.internal.homeConfig ? "apps.ai.orca") && !(off.othrys.internal.persist ? "apps.ai.orca");
  }
