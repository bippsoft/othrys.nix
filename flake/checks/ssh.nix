# flake/checks/ssh.nix
# CORE. The SSH known hosts and client defaults, read back from the system and
# Home Manager configuration. One host takes the defaults, and one adds a known
# host, turns the forge keys off and overrides a single client directive, which
# has to leave the other defaults in place. A third runs the server, whose
# login settings are read back here and the rest in ./ssh-eval.nix.
{
  hostConfig,
  mkExpectations,
  functioningHost,
}: let
  sshHost = ssh:
    hostConfig [
      functioningHost
      {othrys.services.ssh = {enable = true;} // ssh;}
    ];

  defaults = sshHost {};
  custom = sshHost {
    includeForgeKeys = false;
    knownHosts."nas.example.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEX";
    settings."*".StrictHostKeyChecking = "yes";
  };
  replaced = sshHost {
    knownHosts."github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEX";
  };
  served = sshHost {server.enable = true;};
  certified = sshHost {
    knownHosts."ca.example.com" = {
      certAuthority = true;
      hostNames = ["*.example.com"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEX";
    };
  };

  user = host: host.othrys.system.user.name;
  clientBlock = host: host.home-manager.users.${user host}.programs.ssh.settings."*".data;
  known = host: builtins.attrNames host.programs.ssh.knownHosts;
in
  mkExpectations "othrys-eval-ssh" {
    "the four forge keys are known by default" = known defaults == ["codeberg.org" "git.sr.ht" "github.com" "gitlab.com"];
    "every forge key is an ed25519 key" = builtins.all (h: builtins.substring 0 12 defaults.programs.ssh.knownHosts.${h}.publicKey == "ssh-ed25519 ") (known defaults);
    "an unknown host prompts by default" = (clientBlock defaults).StrictHostKeyChecking == "ask";
    "stored host names are hashed" = (clientBlock defaults).HashKnownHosts;
    "new host keys ask first" = (clientBlock defaults).UpdateHostKeys == "ask";
    "includeForgeKeys = false leaves only the host's entries" = known custom == ["nas.example.com"];
    "a host entry reaches the system known hosts" = custom.programs.ssh.knownHosts."nas.example.com".publicKey != "";
    "settings overrides one directive" = (clientBlock custom).StrictHostKeyChecking == "yes";
    "settings leaves the other defaults in place" = (clientBlock custom).HashKnownHosts && (clientBlock custom).ServerAliveInterval == 60;
    "the client asks for no compression" = !((clientBlock defaults).Compression or false);
    "a known host carries its certificate authority flag and host names" = certified.programs.ssh.knownHosts."ca.example.com".certAuthority && certified.programs.ssh.knownHosts."ca.example.com".hostNames == ["*.example.com"];
    "a known host is named after its attribute by default" = custom.programs.ssh.knownHosts."nas.example.com".hostNames == ["nas.example.com"];
    "the server refuses password login" = !served.services.openssh.settings.PasswordAuthentication;
    "the server refuses root login" = served.services.openssh.settings.PermitRootLogin == "no";
    "the server refuses keyboard-interactive login" = !served.services.openssh.settings.KbdInteractiveAuthentication;
    "a host entry replaces a forge entry of the same name" = builtins.match ".*EXAMPLE.*" replaced.programs.ssh.knownHosts."github.com".publicKey != null;
  }
