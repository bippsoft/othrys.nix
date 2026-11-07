# modules/system/persistence.nix
# Persistence registry, declared on every platform and read by nixosModules.impermanence
#
# Every module names what it keeps across the root wipe in
# othrys.internal.persist, declared below. nixosModules.impermanence
# (./impermanence.nix) reads the registry and is the one file that hands it
# to the impermanence module. A darwin host declares the registry so the
# apps that name their state evaluate there, and nothing reads it.
#
# ANCHOR: app-persistence-index
# App-specific persistence lives in each app's module:
# - Steam → modules/apps/gui/gaming/steam.nix
# - Floorp → modules/apps/gui/floorp/floorp.nixos.nix
# - Signal → modules/apps/gui/signal.nix
# - Plexamp → modules/apps/gui/plexamp.nix
# - Audio → modules/hardware/audio.nix
# - Printing → modules/services/printing.nix
# - Tailscale → modules/services/tailscale.nixos.nix
# - Zsh/Zoxide → modules/system/shell/zsh.nixos.nix
# - Direnv → modules/apps/cli/development.nixos.nix
# - Bluetooth → modules/hardware/wireless/bluetooth.nix
# - WiFi → modules/hardware/wireless/wifi.nix
# - GPG/YubiKey → modules/services/security/yubikey.nixos.nix
# ANCHOR_END: app-persistence-index
{lib, ...}: {
  options.othrys.system.persistence = {
    enable = lib.mkEnableOption "System-critical persistence declarations";
  };

  # ANCHOR: persist-registry
  # Every othrys module that keeps state across the root wipe writes here,
  # keyed by its own option path, and nixosModules.impermanence is the only
  # file that writes the option the impermanence module declares.
  #
  # That option exists only on a host that imports the impermanence module,
  # and a write into an option nothing declares fails whatever condition
  # guards it. A module that wrote there directly made every host import the
  # impermanence module, a host with a persistent root included. This option
  # is declared by othrys itself, so a write to it evaluates everywhere and
  # is read only where the export is imported and impermanence is on.
  #
  # The export also applies the two guards, once. System paths are bound when
  # impermanence is on, and the paths under `user` only when
  # othrys.system.users.enable is on as well, since the impermanence module
  # resolves them against the home of an account that has to exist. No module
  # spells either guard, so none can spell it wrongly.
  #
  # A module with a second condition wraps its own value in lib.mkIf. The key
  # then disappears when the condition is false. lib.mkIf on a single list
  # works as well.
  #
  # The value is a typed submodule, unlike othrys.internal.homeConfig, which
  # is raw. A home-manager contribution carries lib.mkForce and lib.mkDefault
  # that have to reach home-manager unprocessed. A persistence entry is a
  # plain path with an optional owner and mode and carries no priority, so
  # the lists are merged here. That lets two blocks of one module share a
  # key, lets lib.mkIf sit on one list, and reports a misspelt attribute at
  # the module that wrote it.
  #
  # An entry keeps the forms the impermanence module accepts. It is a string,
  # or an attribute set with `directory` or `file` and any of `user`, `group`
  # and `mode`. The export passes each entry on unchanged, and the
  # impermanence module checks the attribute names.
  options.othrys.internal.persist = let
    entries = description:
      lib.mkOption {
        type = lib.types.listOf (lib.types.either lib.types.str (lib.types.attrsOf lib.types.anything));
        default = [];
        inherit description;
      };
  in
    lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          directories = entries "System directories to keep, as absolute paths.";
          files = entries "System files to keep, as absolute paths.";
          user = {
            directories = entries "Directories to keep in the primary user's home, relative to it.";
            files = entries "Files to keep in the primary user's home, relative to it.";
          };
        };
      });
      default = {};
      internal = true;
      # The sub-options would otherwise be listed in the options reference
      # under a parent that is not.
      visible = false;
      example = lib.literalExpression ''{ "services.tailscale".directories = [ "/var/lib/tailscale" ]; }'';
      description = "Per-module persistent paths, keyed by option path, handed to the impermanence module by nixosModules.impermanence.";
    };
  # ANCHOR_END: persist-registry
}
