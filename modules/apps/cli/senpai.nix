# modules/apps/cli/senpai.nix
# senpai, a terminal IRC client for a bouncer, with its password read from a file at connect time
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.senpai;
  othrysTypes = import ../../lib/types.nix {inherit lib;};

  # nix-darwin has no othrys.services.soju, so the lookup falls back there.
  soju = config.othrys.services.soju or {enable = false;};

  ready = cfg.address != null && cfg.nickname != null;
in {
  # ANCHOR: senpai-options
  options.othrys.apps.senpai = {
    enable = lib.mkEnableOption "the senpai IRC client";

    address = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        if soju.enable
        then "irc+insecure://127.0.0.1:${toString soju.port}"
        else null;
      defaultText = lib.literalExpression ''"irc+insecure://127.0.0.1:''${port}" when othrys.services.soju.enable is on, null otherwise'';
      example = "irc.example.com:6697";
      description = ''
        Server senpai connects to, as `host[:port]` or an `ircs://`,
        `irc://` or `irc+insecure://` URL. A bare host uses TLS on port
        6697. With `othrys.services.soju` on the same host, the default is
        soju's plaintext listener on loopback.
      '';
    };

    nickname = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alice";
      description = ''
        Nickname senpai registers with. senpai also uses it as the SASL
        user name unless `settings.username` is set, which is the soju
        account name when the server is a soju bouncer.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      example = "/run/secrets/senpai-password";
      description = ''
        Runtime path to a file holding the SASL password, readable by the
        primary user. senpai reads its first line through `password-cmd`
        each time it connects, so the password stays out of the Nix store
        and the configuration file.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      example = {
        username = "alice";
        channel = ["#nixos"];
        highlight = ["alice"];
      };
      description = ''
        Further `senpai.scfg` directives, merged over the ones this module
        writes. See {manpage}`senpai(5)`. `password` and `password-cmd` are
        refused here, since `passwordFile` covers both without writing the
        secret into the store.
      '';
    };
  };
  # ANCHOR_END: senpai-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.address != null;
        message = "othrys.apps.senpai: address is unset. Name the server, or turn on othrys.services.soju on this host to connect to it.";
      }
      {
        assertion = cfg.nickname != null;
        message = "othrys.apps.senpai: nickname is unset.";
      }
      {
        assertion = !(cfg.settings ? password || cfg.settings ? password-cmd);
        message = "othrys.apps.senpai: settings.password and settings.password-cmd are refused, since the first writes the password into the world-readable store. Set passwordFile instead.";
      }
    ];

    # lastbuffer and laststamp, the open buffer and the read marker, under
    # os.UserCacheDir. The config is a Home Manager link and is not persisted.
    othrys.internal.persist."apps.senpai" = {
      user.directories = [".cache/senpai"];
    };

    # Written only once both required values are set, so a missing one is
    # reported by the assertion above and not by the Home Manager type.
    othrys.internal.homeConfig."apps.senpai" = lib.mkIf ready {
      programs.senpai = {
        enable = true;
        config =
          {
            inherit (cfg) address nickname;
          }
          # senpai runs password-cmd without a shell and reads its first
          # line, so cat from the store depends on nothing in the PATH.
          // lib.optionalAttrs (cfg.passwordFile != null) {
            password-cmd = ["${pkgs.coreutils}/bin/cat" cfg.passwordFile];
          }
          // cfg.settings;
      };
    };
  };
}
