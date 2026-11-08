# modules/services/tailscale.darwin.nix
# The nix-darwin implementation of othrys.services.tailscale
#
# nix-darwin's services.tailscale runs tailscaled under launchd and nothing
# else. It has no unit that runs `tailscale up` with a key or `tailscale set`
# after the daemon starts, so the registration and the settings those two
# carry on NixOS are refused here rather than dropped. tailscaled keeps the
# settings in its state, so a host passes them to `tailscale up` once by
# hand. The firewall nix-darwin manages takes no port list, so openFirewall
# is left unread, and there is no impermanence, so the state directory
# needs no persist entry.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.tailscale;

  # Each option that only `tailscale up` or `tailscale set` applies, when it
  # is set away from what tailscaled does without the flag.
  unapplied =
    lib.optional (cfg.authKeyFile != null) "authKeyFile"
    ++ lib.optional (cfg.baseURL != null) "baseURL"
    ++ lib.optional cfg.ssh "ssh"
    ++ lib.optional cfg.acceptRoutes "acceptRoutes"
    ++ lib.optional (cfg.operator != null) "operator"
    ++ lib.optional (!cfg.acceptDns) "acceptDns"
    ++ lib.optional cfg.ephemeral "ephemeral";
in {
  imports = [./tailscale.nix];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = unapplied == [];
        message = "othrys.services.tailscale sets ${lib.concatStringsSep ", " unapplied} on a darwin host, and nix-darwin runs no `tailscale up` or `tailscale set` to apply them. Unset them and pass the matching flags to `tailscale up` once by hand, since tailscaled keeps them in its state.";
      }
    ];

    services.tailscale.enable = true;
  };
}
