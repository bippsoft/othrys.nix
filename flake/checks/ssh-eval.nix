# flake/checks/ssh-eval.nix
# CORE. What the SSH server module hands sshd, the firewall and fail2ban, read
# back from evaluated hosts. A server moved off port 22 has to open that port
# and no other, the sshd jail has to name it, and every hardened setting has
# to stay a default a host replaces with a plain assignment. A wrong port or a
# misspelled directive evaluates cleanly.
{
  hostConfig,
  mkExpectations,
  functioningHost,
}: let
  host = extra:
    hostConfig [
      functioningHost
      {
        othrys.services.ssh = {
          enable = true;
          server.enable = true;
        };
        othrys.services.security.fail2ban.enable = true;
      }
      extra
    ];

  standard = host {};
  moved = host {othrys.services.ssh.server.ports = [2222];};
  # The same port set on the upstream option, which the module's default loses to.
  movedUpstream = host {services.openssh.ports = [2222];};
  closed = host {
    othrys.services.ssh.server = {
      ports = [2222];
      openFirewall = false;
    };
  };
  # Plain assignments, with no mkForce.
  loosened = host {
    services.openssh.settings = {
      MaxAuthTries = 6;
      AllowTcpForwarding = "yes";
    };
  };
  clientOnly = hostConfig [
    functioningHost
    {othrys.services.ssh.enable = true;}
  ];

  sshd = cfg: cfg.services.openssh.settings;
  opened = cfg: cfg.networking.firewall.allowedTCPPorts;
  jailPort = cfg: cfg.services.fail2ban.jails.sshd.settings.port;

  expected = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    X11Forwarding = false;
    UsePAM = true;
    AllowTcpForwarding = "no";
    AllowAgentForwarding = "no";
    MaxAuthTries = 3;
    LoginGraceTime = 30;
    MaxSessions = 4;
    ClientAliveInterval = 300;
    ClientAliveCountMax = 2;
    LogLevel = "VERBOSE";
    KexAlgorithms = [
      "sntrup761x25519-sha512@openssh.com"
      "mlkem768x25519-sha256"
      "curve25519-sha256"
      "curve25519-sha256@libssh.org"
    ];
    Ciphers = [
      "chacha20-poly1305@openssh.com"
      "aes256-gcm@openssh.com"
      "aes128-gcm@openssh.com"
      "aes256-ctr"
    ];
    Macs = [
      "hmac-sha2-512-etm@openssh.com"
      "hmac-sha2-256-etm@openssh.com"
    ];
  };
in
  mkExpectations "othrys-eval-ssh-settings" (
    builtins.listToAttrs (map (key: {
      name = "the server default for ${key} is written";
      value = ((sshd standard).${key} or null) == expected.${key};
    }) (builtins.attrNames expected))
    // {
      "the server listens on 22 by default" = standard.services.openssh.ports == [22];
      "the default port is opened" = builtins.elem 22 (opened standard);
      "the default jail names port 22" = jailPort standard == "22";
      "a moved server listens on its port alone" = moved.services.openssh.ports == [2222];
      "a moved server opens its port" = builtins.elem 2222 (opened moved);
      "a moved server leaves port 22 closed" = !builtins.elem 22 (opened moved);
      "the jail names the moved port" = jailPort moved == "2222";
      "a port set on the upstream option replaces the default" = movedUpstream.services.openssh.ports == [2222];
      "a port set on the upstream option is the one opened" = builtins.elem 2222 (opened movedUpstream) && !builtins.elem 22 (opened movedUpstream);
      "the jail names a port set on the upstream option" = jailPort movedUpstream == "2222";
      "openFirewall = false opens no server port" = !builtins.elem 2222 (opened closed) && !builtins.elem 22 (opened closed);
      "the jail names the port of a server the firewall leaves closed" = jailPort closed == "2222";
      "a plain MaxAuthTries replaces the default" = (sshd loosened).MaxAuthTries == 6;
      "a plain AllowTcpForwarding replaces the default" = (sshd loosened).AllowTcpForwarding == "yes";
      "an override leaves the other defaults in place" = (sshd loosened).LoginGraceTime == 30 && (sshd loosened).AllowAgentForwarding == "no";
      "the client alone starts no server" = !clientOnly.services.openssh.enable;
      "the client alone opens no port" = !builtins.elem 22 (opened clientOnly);
    }
  )
