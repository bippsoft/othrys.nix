# modules/services/mosh.nix
# Mosh, the mobile shell, which keeps a session through sleep and a change of network
{lib, ...}: {
  # ANCHOR: mosh-options
  options.othrys.services.mosh = {
    enable = lib.mkEnableOption "Mosh server and client";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open UDP 60000 to 61000, the range mosh-server picks its port from,
        in the NixOS firewall. A host that only connects out to other hosts
        turns it off. nix-darwin's firewall takes no port list, so it is
        unread there.
      '';
    };
  };
  # ANCHOR_END: mosh-options
}
