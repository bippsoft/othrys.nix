# flake/checks/pam-eval.nix
# CORE. Which PAM services take the YubiKey and with what control, read back
# from an evaluated desktop host. The global switch once put pam_u2f into
# every service as `sufficient`, so a touch alone passed su, polkit and the
# lockers while the option text promised two factors, and nothing in that
# fails evaluation.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  functioningHost,
}: let
  credential = "AAAA,BBBB,es256,+presence";
  host = extra:
    hostConfig [
      functioningHost
      {
        othrys.system.stylix.enable = true;
        othrys.desktop.compositors.hyprland.enable = true;
        othrys.desktop.login.enable = true;
        othrys.desktop.idle.enable = true;
        othrys.desktop.ashell.enable = true;
        othrys.services.security = {
          sudo.enable = true;
          polkit.enable = true;
          yubikey = {
            enable = true;
            u2fMappings.alice = [credential];
          };
        };
      }
      extra
    ];

  twoFactor = host {};
  touchAlone = host {othrys.services.security.yubikey.u2fRequirePassword = false;};
  unmapped = host ({lib, ...}: {othrys.services.security.yubikey.u2fMappings = lib.mkForce {bob = [credential];};});
  unmappedTouchAlone = host ({lib, ...}: {
    othrys.services.security.yubikey = {
      u2fMappings = lib.mkForce {bob = [credential];};
      u2fRequirePassword = false;
    };
  });
  noKey = host ({lib, ...}: {othrys.services.security.yubikey.u2fMappings = lib.mkForce {};});

  services = cfg: cfg.security.pam.services;
  listed = ["login" "sudo" "greetd" "polkit-1" "hyprlock" "swaylock"];
  allHave = control: cfg: builtins.all (name: (services cfg).${name}.u2f.enable && (services cfg).${name}.u2f.control == control) listed;
in
  mkExpectations "othrys-eval-pam" {
    "the global u2f switch stays off" = !twoFactor.security.pam.u2f.enable;
    "every listed service takes the key as required by default" = allHave "required" twoFactor;
    "touch alone makes every listed service sufficient" = allHave "sufficient" touchAlone;
    "su does not take the key" = !(services twoFactor).su.u2f.enable;
    "sshd does not take the key" = !((services twoFactor).sshd.u2f.enable or false);
    "the mappings file is in the store and named in the settings" = builtins.match "/nix/store/.*u2f-mappings" (toString twoFactor.security.pam.u2f.settings.authfile) != null;
    "no ENTER prompt, only the touch cue" = !twoFactor.security.pam.u2f.settings.interactive && twoFactor.security.pam.u2f.settings.cue;
    "required with no mapping for the primary user is rejected" = rejectedWith "would lock that user out" unmapped;
    "sufficient with no mapping for the primary user is accepted" = !rejectedWith "lock" unmappedTouchAlone;
    "no mapping at all leaves every service alone" = !builtins.any (name: (services noKey).${name}.u2f.enable) listed;
    "sudo runs commands in a pseudo-terminal with a timeout" = builtins.match ".*Defaults use_pty.*Defaults timestamp_timeout=5.*" twoFactor.security.sudo.extraConfig != null;
  }
