# modules/services/security/sudo.nix
# Sudo configuration
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.security.sudo;
in {
  options.othrys.services.security.sudo = {
    enable = lib.mkEnableOption "Sudo configuration";

    execWheelOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Only allow users in the wheel group to run sudo at all.";
    };

    timestampTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 5;
      description = ''
        Minutes a successful authentication is reused for before sudo asks
        again (`Defaults timestamp_timeout`). sudo's own default is 5, and 0
        asks every time.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    security.sudo = {
      enable = true;
      wheelNeedsPassword = true;
      inherit (cfg) execWheelOnly;
      # use_pty runs the command in its own pseudo-terminal, so a command
      # cannot inject keystrokes into the caller's terminal after it ends.
      extraConfig = ''
        Defaults use_pty
        Defaults timestamp_timeout=${toString cfg.timestampTimeout}
      '';
    };
  };
}
