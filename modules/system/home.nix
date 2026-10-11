# modules/system/home.nix
# Home Manager adapter, which hands the per-user registry to the Home Manager module
#
# Exported as nixosModules.home and left out of nixosModules.default, so a
# host imports it together with the Home Manager module or imports neither.
# It is the only file in this tree that writes home-manager.users, and the
# only one that sets the two package options below.
#
# The registry it reads, othrys.internal.homeConfig, and the options
# othrys.system.users.homeManager.enable and othrys.system.users.homeManaged
# are declared in ./users.nix, which is part of nixosModules.default. A
# module can therefore name its user configuration on a host that imports no
# Home Manager module at all, where the entries are skipped and reported.
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.system.users;
in {
  config = lib.mkMerge [
    {
      # What homeManaged and the assertion in ./users.nix read. It is true on
      # every host that imports this file, whether or not a user is managed.
      othrys.internal.homeExport = true;

      # ANCHOR: home-splice
      # The guard is applied here, once, and at the attribute-set level.
      # homeManaged implies othrys.system.users.enable, so the user name is
      # read only on a host that has the account. A guard on a leaf would
      # still declare the Home Manager user and trip the NixOS account
      # assertions on a host without one.
      home-manager.users = lib.mkIf cfg.homeManaged {
        ${username} = lib.mkMerge (
          # Essential user CLI tools, kept here rather than in
          # environment.systemPackages so they follow the user.
          [{home.packages = with pkgs; [tree jq just];}]
          ++ lib.attrValues config.othrys.internal.homeConfig
        );
      };
      # ANCHOR_END: home-splice
    }

    (lib.mkIf config.othrys.system.nix.enable {
      # Home Manager must see the same nixpkgs policy as the system (unfree,
      # overlays). With its own instantiation, an unfree Home Manager package
      # fails even though othrys.system.nix.allowUnfree is on. Both follow
      # othrys.system.nix, as they did while that module set them, and
      # mkDefault leaves the host the last word.
      home-manager.useGlobalPkgs = lib.mkDefault true;
      home-manager.useUserPackages = lib.mkDefault true;
    })
  ];
}
