# modules/apps/cli/ai/t3code.nixos.nix
# The NixOS implementation of othrys.apps.ai.t3code
#
# The headless server is a systemd user unit, restarted whenever it exits.
# Where othrys manages the user with Home Manager, the user lingers, so the
# manager starts at boot and stays after the last logout, and the server
# runs with nobody logged in. Upstream's
# `t3 service install` writes a unit of its own around a runtime it updates
# itself, which a binary from the store cannot be.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.ai.t3code;
  user = config.othrys.system.user.name;
  headless = cfg.enable && cfg.mode == "headless";
in {
  imports = [./t3code.nix];

  config = lib.mkIf headless {
    othrys.internal.homeConfig."apps.ai.t3code-service" = {
      systemd.user.services.t3code = {
        Unit = {
          Description = "T3 Code server";
          # The tailnet address may be missing for a while after boot, and
          # the unit keeps trying until tailscaled has one.
          StartLimitIntervalSec = 0;
        };
        Service = {
          ExecStart = "${config.othrys.internal.t3code.serve}";
          Restart = "always";
          RestartSec = 10;
          # The agents run git, the user's own tools and the setuid
          # wrappers, which a user unit does not find on its own PATH. git
          # stays last, for a host whose profile has none.
          Environment = ["PATH=/run/wrappers/bin:/etc/profiles/per-user/${user}/bin:/run/current-system/sw/bin:${pkgs.git}/bin"];
        };
        Install.WantedBy = ["default.target"];
      };
    };

    # An account write that serves the Home Manager unit above, so it waits
    # on homeManaged, which holds only with othrys.system.users.enable.
    users.users = lib.mkIf config.othrys.system.users.homeManaged {
      ${user}.linger = true;
    };

    networking.firewall = lib.mkMerge [
      (lib.mkIf (cfg.listen == "lan") {
        allowedTCPPorts = [cfg.port];
      })
      (lib.mkIf (cfg.listen == "tailscale") {
        interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [cfg.port];
      })
    ];
  };
}
