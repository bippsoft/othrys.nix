# modules/services/ssh.nix
# SSH server and client configuration - Integration Pattern
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.ssh;

  # The ed25519 host keys the forges publish, each checked against the forge's
  # own documentation over HTTPS (GitHub's /meta API, the GitLab.com and
  # Codeberg fingerprint pages, the git.sr.ht manual). A forge that rotates its
  # key makes the entry here stale, and ssh then refuses that forge until the
  # entry is updated or includeForgeKeys is turned off.
  forgeKeys = {
    "github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    "gitlab.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";
    "codeberg.org".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIVIC02vnjFyL+I4RHfvIGNtOgJMe769VTF1VR4EB3ZB";
    "git.sr.ht".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZvRd4EtM7R+IHVMWmDkVU3VLQTSwQDSAvW0t2Tkj60";
  };

  # One known host, with the options programs.ssh.knownHosts declares for an
  # entry. Declaring them here rejects a misspelled key at this option, where
  # the error names the host's own definition.
  knownHost = {
    name,
    config,
    ...
  }: {
    options = {
      publicKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...";
        description = "The key type and the key, without any host name.";
      };
      publicKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "A file holding one public key, read at build time and copied into the Nix store.";
      };
      hostNames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [name] ++ config.extraHostNames;
        defaultText = lib.literalExpression "[ <name> ] ++ extraHostNames";
        description = "Names and addresses the key is trusted for. The attribute name is included by default.";
      };
      extraHostNames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Further names and addresses beside the attribute name. Ignored when `hostNames` is set.";
      };
      certAuthority = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "The key is a certificate authority that signs host keys.";
      };
    };
  };
in {
  options.othrys.services.ssh = {
    enable = lib.mkEnableOption "SSH server and client";

    server = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the inbound SSH server. Opt-in per host so exposure is explicit.";
      };

      ports = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [22];
        example = [2222];
        description = ''
          Ports the server listens on, passed to `services.openssh.ports` as a
          default. The firewall and the fail2ban sshd jail both read the
          upstream option, so a host that sets `services.openssh.ports` itself
          gets the same result.
        '';
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Open the server's ports in the firewall. Unlike most othrys firewall
          toggles this defaults to true, since enabling the server is already
          the explicit decision to expose it. Turn it off on a host that opens
          the port on named interfaces only.
        '';
      };
    };

    knownHosts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule knownHost);
      default = {};
      example = lib.literalExpression ''
        {
          "nas.example.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...";
        }
      '';
      description = ''
        Host keys every user on this host trusts, passed to
        `programs.ssh.knownHosts` and written to `/etc/ssh/ssh_known_hosts`. A
        host listed here is verified against the listed key on the first
        connection, so nobody is asked to accept it on trust. Each entry needs
        one of `publicKey` and `publicKeyFile`. Host names and keys are identity
        and belong in the host configuration.
      '';
    };

    includeForgeKeys = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add the published ed25519 host keys of github.com, gitlab.com,
        codeberg.org and git.sr.ht to the known hosts. They are public keys of
        public services. Turn this off to manage those entries yourself.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      description = ''
        Additional SSH client config blocks, merged with module defaults and
        written to ~/.ssh/config. Keys are literal OpenSSH directive names. A
        directive set under `"*"` replaces the module's default for that
        directive and leaves the others in place.

        The defaults keep `StrictHostKeyChecking ask`, so an unknown host still
        prompts and is never accepted silently. Once `knownHosts` lists every
        host this machine connects to, set `"*".StrictHostKeyChecking = "yes"`,
        which refuses any host that is not listed and ends trust on first use.
      '';
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
    # The forge keys come first so a host entry of the same name replaces one.
    programs.ssh.knownHosts = lib.optionalAttrs cfg.includeForgeKeys forgeKeys // cfg.knownHosts;

    services.openssh = lib.mkIf cfg.server.enable {
      enable = true;
      # Both are defaults, so a host that sets the upstream options directly
      # wins. Upstream opens whatever services.openssh.ports ends up holding,
      # which keeps the firewall and the listener on the same list.
      ports = lib.mkDefault cfg.server.ports;
      openFirewall = lib.mkDefault cfg.server.openFirewall;

      # Hardened defaults, with mkDefault so a host can loosen one (e.g. temporary
      # PasswordAuthentication during bootstrap) without lib.mkForce.
      settings = {
        PermitRootLogin = lib.mkDefault "no";
        PasswordAuthentication = lib.mkDefault false;
        KbdInteractiveAuthentication = lib.mkDefault false;
        X11Forwarding = lib.mkDefault false;

        # PAM stays on. With password and keyboard-interactive login off it
        # authenticates nobody, and sshd still runs the account and session
        # stacks through it, which is what opens the systemd-logind session
        # and applies limits. A host that puts pam_u2f into the sshd service
        # needs it as well.
        UsePAM = lib.mkDefault true;

        # Forwarding turns a login into a tunnel into the host's network and
        # hands the client's agent to anyone with root on the host. A host
        # that is a jump host or serves remote editors turns these back on.
        AllowTcpForwarding = lib.mkDefault "no";
        AllowAgentForwarding = lib.mkDefault "no";

        MaxAuthTries = lib.mkDefault 3;
        LoginGraceTime = lib.mkDefault 30;
        MaxSessions = lib.mkDefault 4;
        # A client that answers no keepalive for ten minutes is disconnected.
        ClientAliveInterval = lib.mkDefault 300;
        ClientAliveCountMax = lib.mkDefault 2;

        # VERBOSE logs the fingerprint of the key behind every login, and it
        # is the level the fail2ban sshd filter reads.
        LogLevel = lib.mkDefault "VERBOSE";

        # Explicit lists, narrower than the set nixpkgs recommends. They drop
        # the finite-field group exchange, the 128 and 192 bit CTR ciphers and
        # umac. Every client since OpenSSH 6.5 supports curve25519 with
        # chacha20-poly1305, while an older one needs an entry added back.
        KexAlgorithms = lib.mkDefault [
          "sntrup761x25519-sha512@openssh.com"
          "mlkem768x25519-sha256"
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
        ];
        Ciphers = lib.mkDefault [
          "chacha20-poly1305@openssh.com"
          "aes256-gcm@openssh.com"
          "aes128-gcm@openssh.com"
          "aes256-ctr"
        ];
        Macs = lib.mkDefault [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
        ];
      };
    };

    othrys.internal.homeConfig."services.ssh".programs.ssh = {
      enable = true;
      enableDefaultConfig = false;

      # recursiveUpdate, so a host that sets one directive under "*" keeps the
      # rest of the defaults.
      settings =
        lib.recursiveUpdate {
          "*" = {
            SetEnv = {
              TERM = "xterm-256color";
            };
            ServerAliveInterval = 60;
            ServerAliveCountMax = 3;
            # An unknown host prompts and is never accepted silently, stored
            # host names are hashed, and a host offering new keys asks first.
            StrictHostKeyChecking = "ask";
            HashKnownHosts = true;
            UpdateHostKeys = "ask";
          };
        }
        cfg.settings;

      extraConfig = ''
        AddKeysToAgent yes
      '';
    };
  };
}
