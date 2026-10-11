# modules/desktop/keyring.nix
# Secret Service provider for the graphical session, on gnome-keyring
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.desktop.keyring;
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
  niriEnabled = config.othrys.desktop.compositors.niri.enable;
in {
  # ANCHOR: keyring-options
  options.othrys.desktop.keyring = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.othrys.desktop.graphical;
      defaultText = lib.literalExpression "config.othrys.desktop.graphical";
      example = false;
      description = ''
        Whether to run gnome-keyring as the Secret Service provider of the
        graphical session. Browsers, mail clients and tray applications store
        credentials in the Secret Service, and without a provider they fall
        back to a plain file or ask again on every start. It is on by default
        on a graphical host. A host that runs another provider, such as
        KeePassXC or KWallet, turns it off, since two providers compete for
        the same D-Bus name.
      '';
    };
  };
  # ANCHOR_END: keyring-options

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      services.gnome.gnome-keyring.enable = true;

      # The greeter hands the login password to the keyring, which unlocks it
      # with the session. Without this the first application that asks for a
      # secret raises a second password prompt.
      security.pam.services = lib.mkIf config.othrys.desktop.login.enable {
        greetd.enableGnomeKeyring = true;
      };

      environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
        users.${username}.directories = [
          {
            directory = ".local/share/keyrings";
            mode = "0700";
          }
        ];
      };
    })

    # niri-flake's NixOS module enables gnome-keyring on every niri host as a
    # plain definition, which the option default cannot answer. A definition
    # one step above it lets the option turn the keyring off there, and a host
    # that wants the last word still has mkForce. It is written on niri hosts
    # only, so that elsewhere a host's own gnome-keyring setting is left alone.
    (lib.mkIf (!cfg.enable && niriEnabled) {
      services.gnome.gnome-keyring.enable = lib.mkOverride 90 false;
    })
  ];
}
