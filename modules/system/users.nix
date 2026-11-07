# modules/system/users.nix
# Options of othrys.system.users and the Home Manager registry
{
  config,
  lib,
  pkgs,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.system.users;
in {
  options.othrys.system.users = {
    enable = lib.mkEnableOption "User account configuration";

    homeManager = {
      enable =
        lib.mkEnableOption "home-manager management of the primary user's environment"
        // {default = true;};
    };

    # Derived and read-only, the single flag every module reads to learn
    # whether Home Manager manages the primary user. Account creation (enable)
    # and environment management (homeManager.enable) are separate concerns,
    # since a server may want a login account (e.g. for an admin, or a user a
    # webapp runs under) without home-manager owning its dotfiles.
    #
    # The third term is the export. The registry below is applied by
    # nixosModules.home (./home.nix) and by nothing else, so on a host that
    # leaves the export out no Home Manager configuration reaches the user,
    # and every module has to behave as it does for an unmanaged one.
    homeManaged = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = cfg.enable && cfg.homeManager.enable && config.othrys.internal.homeExport;
      defaultText = lib.literalExpression "othrys.system.users.enable && othrys.system.users.homeManager.enable, on a host that imports nixosModules.home";
      description = ''
        Whether home-manager manages the primary user (derived; do not set).
        True when the account exists, `homeManager.enable` is on and the host
        imports `nixosModules.home` beside the Home Manager module.
      '';
    };

    defaultShell = lib.mkOption {
      type = lib.types.package;
      default = pkgs.bash;
      defaultText = lib.literalExpression "pkgs.bash";
      description = "Default shell for the user.";
    };

    initialHashedPassword = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "$y$j9T$...";
      description = ''
        Hashed password used to bootstrap the account on first boot, for the
        window before a secrets provider is available. Generate one with
        `mkpasswd -m yescrypt`.

        The hash is written into the world-readable Nix store and stays there
        for the life of every generation that references it, so treat it as
        public and offline-crackable. It is a bootstrap mechanism, and NixOS
        does not clear or expire it. Move the host to passwordFile once secrets
        decrypt on boot.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      example = lib.literalExpression "config.sops.secrets.\"users/alice/password\".path";
      description = ''
        Path to a runtime file holding the hashed password, injected by the
        host configuration. The preferred form, since nothing reaches the
        store.

        The file is read in the `users` activation step, before ordinary
        secrets are installed. With sops-nix only a secret declared with
        `neededForUsers = true` exists in time, and such a secret lives under
        `/run/secrets-for-users/`, not `/run/secrets/`. A path that is absent
        when the step runs leaves the account with no usable password, and
        the module warns on a `/run/secrets/` prefix for that reason.
      '';
    };

    mutableUsers = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        users.mutableUsers. False keeps accounts fully declarative, so passwd
        and useradd changes do not survive a rebuild. Set it to true on a host
        where accounts are managed outside Nix.

        This is stated rather than inferred. It was previously derived from
        whether passwordFile happened to be null, which flipped a security
        property as a side effect of an unrelated option.
      '';
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional groups for the user, beside `wheel` when the `wheel` option is on.";
    };

    wheel = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Put the primary user in `wheel`, which is sudo. Off for a host whose
        primary user is not its administrator.
      '';
    };
  };

  # Every othrys module that configures the primary user's environment writes
  # here, keyed by its own option path. This file declares the registry and
  # writes into no option of the home-manager flake. nixosModules.home
  # (./home.nix) is the one file that hands the registry to
  # home-manager.users, and a host imports it together with the Home Manager
  # module or imports neither.
  #
  # The consumer contract requires those writes to sit behind homeManaged at
  # the attrset level, since a leaf-level guard still materializes the
  # home-manager user and trips NixOS's account assertions on a host with no
  # primary user. Routing every module through one option means no module can
  # spell that guard wrongly, and it lets flake/checks/ enforce the rule as a
  # prohibition (nothing but the export writes home-manager.users) rather than
  # a correlation (a module that writes it must also mention homeManaged). A
  # prohibition cannot be satisfied by accident.
  #
  # A module with a second condition wraps its own value in lib.mkIf. The key
  # then disappears when the condition is false, so it is neither written nor
  # reported by the warning in users.nixos.nix.
  # lib.types.raw rather than attrsOf anything, and the difference is not
  # cosmetic. Every ordinary option type resolves definition priorities at its
  # own level, so a module writing `gtk.gtk4.theme = lib.mkForce null` through
  # an `anything`-typed option would have that mkForce discharged here and
  # arrive at home-manager as a plain definition, silently losing to an
  # upstream one. raw passes each value through unprocessed, so mkForce and mkDefault
  # inside a module's contribution still reach home-manager.users and still
  # win or lose against upstream as the module intended. A top-level mkIf is
  # unaffected either way, since definition properties are discharged before
  # the type sees the value.
  #
  # raw also refuses to merge two definitions of the same key. Keys are option
  # paths and therefore unique per module, so a collision is a bug and failing
  # loudly is the right answer.
  options.othrys.internal.homeConfig = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = {};
    internal = true;
    example = lib.literalExpression ''{ "apps.ghostty" = { programs.ghostty.enable = true; }; }'';
    description = "Per-module home-manager configuration for the primary user, keyed by option path, handed to Home Manager by nixosModules.home.";
  };

  # Set by nixosModules.home (./home.nix) and by nothing else. It is what
  # homeManaged and the assertion in users.nixos.nix read to learn whether
  # the registry reaches Home Manager on this host. The option carries a default and is
  # therefore not read-only, since the module system counts the default of a
  # read-only option as its one definition.
  options.othrys.internal.homeExport = lib.mkOption {
    type = lib.types.bool;
    default = false;
    internal = true;
    description = "Whether nixosModules.home is imported (set by that export, do not set).";
  };
}
