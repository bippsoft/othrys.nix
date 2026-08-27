# modules/services/ssh.nix
# SSH server and client configuration - Integration Pattern
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  hmEnabled = config.othrys.system.users.homeManaged;
  cfg = config.othrys.services.ssh;
in {
  options.othrys.services.ssh = {
    enable = lib.mkEnableOption "SSH server and client";

    server = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the inbound SSH server. Opt-in per host so exposure is explicit.";
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      description = "Additional SSH client config blocks, merged with module defaults and written to ~/.ssh/config. Keys are literal OpenSSH directive names.";
      example = lib.literalExpression ''
        {
          "myhost" = {
            Hostname = "myhost.example.com";
            User = "admin";
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh = lib.mkIf cfg.server.enable {
      enable = true;
      # Hardened defaults, with mkDefault so a host can loosen one (e.g. temporary
      # PasswordAuthentication during bootstrap) without lib.mkForce.
      settings = {
        PermitRootLogin = lib.mkDefault "no";
        PasswordAuthentication = lib.mkDefault false;
        KbdInteractiveAuthentication = lib.mkDefault false;
        X11Forwarding = lib.mkDefault false;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.server.enable [22];

    # Per-user state only when othrys manages the user account, guarded at the
    # attrset level so headless hosts never materialize a home-manager user
    # (see modules/system/nix.nix).
    home-manager.users = lib.mkIf hmEnabled {
      ${username}.programs.ssh = {
        enable = true;
        enableDefaultConfig = false;

        settings =
          {
            "*" = {
              SetEnv = {
                TERM = "xterm-256color";
              };
              ServerAliveInterval = 60;
              ServerAliveCountMax = 3;
              Compression = true;
            };
          }
          // cfg.settings;

        extraConfig = ''
          AddKeysToAgent yes
        '';
      };
    };
  };
}
