# modules/system/users.nixos.nix
# The NixOS implementation of othrys.system.users
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.system.users;
in {
  imports = [./users.nix];

  config = lib.mkMerge [
    {
      # The warning sits outside the enable guard, since it reports the
      # case where enable is off and gating it on enable could never fire.
      #
      # Most modules that configure the user write nothing else, so on a host
      # without a managed user `enable = true` silently does nothing at all.
      # One warning naming every such module, since thirty-two near-identical
      # ones on every rebuild is how a diagnostic gets scrolled past.
      # attrNames returns sorted, so the list is stable across evaluations.
      warnings = lib.optional (!cfg.homeManaged && config.othrys.internal.homeConfig != {}) ''
        othrys.system.users.homeManaged is false, so home-manager configuration was
        skipped for: ${lib.concatStringsSep ", " (lib.attrNames config.othrys.internal.homeConfig)}.

        Where a module writes nothing but user configuration, enabling it on this
        host has no effect at all. Set othrys.system.users.enable and
        othrys.system.users.homeManager.enable to apply them, and import
        othrys.nixosModules.home together with the nixosModules.home-manager of
        the home-manager flake, which is the module that applies them.
      '';
    }

    (lib.mkIf cfg.enable {
      # Fail loudly rather than create a passwordless/locked account on first boot.
      assertions = [
        {
          assertion = cfg.passwordFile != null || cfg.initialHashedPassword != null;
          message = "othrys.system.users: set passwordFile or initialHashedPassword, or the '${username}' account is created with no password.";
        }
        # The registry is read by the export alone. Without it the account
        # is created and every module that configures the user, which for
        # most of them is all they do, is skipped. A host that wants the
        # account and no Home Manager says so with homeManager.enable.
        {
          assertion = !cfg.homeManager.enable || config.othrys.internal.homeExport;
          message = "othrys.system.users: enable and homeManager.enable are set and nixosModules.home is not imported, so no module's Home Manager configuration would reach the '${username}' account. Import othrys.nixosModules.home together with the nixosModules.home-manager of the home-manager flake, or set othrys.system.users.homeManager.enable = false for an account Home Manager does not manage.";
        }
      ];

      # NixOS reads hashedPasswordFile in the `users` activation step, and
      # sops-nix installs ordinary secrets after it. A sops secret declared
      # with neededForUsers lands under /run/secrets-for-users/ instead, so a
      # /run/secrets/ path is the one that is missing at the moment it is
      # read. The result is a shadow entry nobody can log in with, and the
      # host reports nothing, so this says so at evaluation.
      warnings = lib.optional (cfg.passwordFile != null && lib.hasPrefix "/run/secrets/" cfg.passwordFile) ''
        othrys.system.users.passwordFile is ${cfg.passwordFile}, under /run/secrets/.
        sops-nix installs that path after the users activation step reads it,
        so the '${username}' account comes up with no usable password. Declare
        the secret with neededForUsers = true and use its path, which is under
        /run/secrets-for-users/.
      '';

      # User creation, secrets-agnostic since passwordFile is injected by the host config
      users.users.${username} = {
        isNormalUser = true;
        description = username;

        extraGroups = lib.optional cfg.wheel "wheel" ++ cfg.extraGroups;

        shell = cfg.defaultShell;

        # Use the injected password file, or fall back to the bootstrap hash.
        hashedPasswordFile = cfg.passwordFile;
        initialHashedPassword = lib.mkIf (cfg.passwordFile == null) cfg.initialHashedPassword;
      };

      users.mutableUsers = cfg.mutableUsers;

      # Essential system and recovery packages, kept minimal since user CLI
      # tools go to Home Manager (see ./home.nix).
      environment.systemPackages = with pkgs; [
        curl
        wget
        vim
        unzip
        zip
        lsof
        pciutils
      ];
    })
  ];
}
