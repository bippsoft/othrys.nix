# modules/apps/cli/ai/paseo.nixos.nix
# The NixOS implementation of othrys.apps.ai.paseo
#
# The daemon is a systemd user unit, restarted whenever it exits. Where
# othrys manages the user with Home Manager, the user lingers, so the manager
# starts at boot and stays after the last logout, and the daemon runs with
# nobody logged in.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.ai.paseo;
  user = config.othrys.system.user.name;
  service = cfg.enable && cfg.service.enable;
in {
  imports = [./paseo.nix];

  config = lib.mkIf service {
    othrys.internal.homeConfig."apps.ai.paseo-service" = {
      systemd.user.services.paseo = {
        Unit = {
          Description = "Paseo daemon";
          # The tailnet address may be missing for a while after boot, and
          # the unit keeps trying until tailscaled has one.
          StartLimitIntervalSec = 0;
        };
        Service = {
          ExecStart = "${config.othrys.internal.paseo.serve}";
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
