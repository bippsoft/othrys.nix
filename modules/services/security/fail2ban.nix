# modules/services/security/fail2ban.nix
# Intrusion prevention - SSH brute force protection
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.security.fail2ban;
in {
  # ANCHOR: fail2ban-options
  options.othrys.services.security.fail2ban = {
    enable = lib.mkEnableOption "Fail2ban intrusion prevention";

    maxretry = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "Failures before a ban (applies to the base config and the sshd jail).";
    };

    bantime = lib.mkOption {
      type = lib.types.str;
      default = "10m";
      description = "Base ban duration (escalated by bantime-increment up to 48h).";
    };

    ignoreIP = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "127.0.0.1/8"
        "::1"
      ];
      example = [
        "127.0.0.1/8"
        "::1"
        "100.64.0.0/10"
      ];
      description = ''
        Addresses exempt from banning. Loopback only by default. Tailnet
        peers are NOT exempt, since exempting the Tailscale CGNAT range
        (100.64.0.0/10) would let every tailnet node bypass fail2ban (shared
        Headscale, third-party devices). Hosts that fully trust their tailnet
        can add it explicitly.
      '';
    };
  };
  # ANCHOR_END: fail2ban-options

  config = lib.mkIf cfg.enable {
    services.fail2ban = {
      enable = true;
      inherit (cfg) maxretry bantime ignoreIP;

      bantime-increment = {
        enable = true;
        maxtime = "48h";
        factor = "4";
        formula = "ban.Time * (1<<(ban.Count if ban.Count<20 else 20)) * banFactor";
        overalljails = true;
      };

      # Only watch SSH auth logs when the SSH server is actually enabled.
      jails = lib.mkIf config.services.openssh.enable {
        sshd = {
          settings = {
            enabled = true;
            port = "ssh";
            filter = "sshd[mode=aggressive]";
            inherit (cfg) maxretry bantime;
            findtime = "10m";
          };
        };
      };
    };

    services.openssh.settings.LogLevel = lib.mkIf config.services.openssh.enable (lib.mkDefault "VERBOSE");
  };
}
