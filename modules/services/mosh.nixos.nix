# modules/services/mosh.nixos.nix
# The NixOS implementation of othrys.services.mosh
#
# programs.mosh installs mosh, and with openFirewall it opens UDP 60000 to
# 61000, the range mosh-server picks its port from, in the NixOS firewall.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.mosh;
in {
  imports = [./mosh.nix];

  config = lib.mkIf cfg.enable {
    programs.mosh = {
      enable = true;
      inherit (cfg) openFirewall;
    };
  };
}
