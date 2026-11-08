# modules/theme/stylix.nixos.nix
# The NixOS implementation of othrys.system.stylix
#
# Exported as nixosModules.stylix and left out of nixosModules.default, so a
# host imports it together with the Stylix module or imports neither. What
# both platforms write is in stylix.nix. This file holds the Stylix targets
# and the cursor that exist on NixOS alone.
{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  cfg = config.othrys.system.stylix;
  guiEnabled = cfg.gui.enable;
in {
  imports = [./stylix.nix];

  config = lib.mkMerge [
    # niri-flake adds its Stylix target to every Home Manager user on a host
    # that declares the `stylix` option namespace, and that target reads the
    # Home Manager option `stylix.enable`. Stylix declares the option there
    # only while it is enabled, so a host that imports both and leaves Stylix
    # off would fail to evaluate. A minimal `stylix.enable = false` is
    # declared for that case, and the target's guard then short-circuits.
    # With Stylix on, its own Home Manager module provides the option.
    (lib.optionalAttrs (options ? home-manager) {
      home-manager.sharedModules = lib.optionals (!config.stylix.enable) [
        {
          options.stylix.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            internal = true;
            description = "Shim for niri-flake's injected Stylix target on hosts without Stylix home-manager config.";
          };
        }
      ];
    })

    # stylix.nix turns Stylix on only once it has a palette, so these follow
    # that and not the othrys option alone.
    (lib.mkIf (cfg.enable && config.stylix.enable) {
      stylix = lib.mkMerge [
        {
          # Application targets, where console/plymouth are the headless-relevant ones
          # and stay on, while GTK theming follows the GUI surface.
          targets = {
            console.enable = true;
            kmscon.enable = false;
            grub.enable = false;
            plymouth = {
              enable = true;
              logoAnimated = true;
            };
            gtk.enable = guiEnabled;
            gnome.enable = false;
          };
        }
        (lib.mkIf guiEnabled {
          # Cursor theme
          cursor = {
            package = lib.mkDefault pkgs.bibata-cursors;
            name = lib.mkDefault "Bibata-Modern-Classic";
            size = lib.mkDefault 24;
          };
        })
      ];
    })
  ];
}
