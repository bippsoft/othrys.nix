# flake/checks/auto-upgrade-eval.nix
# CORE. The verify gate's evaluation-time rules, read back from evaluated
# hosts. The flag denylist once stopped at the three lock rewrites while
# --override-flake, --option and --impure let the evaluation leave the lock
# just the same, and a source frozen at its verified commit was never
# reported. The VM test covers what the unit does at run time, the stale
# report among it.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  functioningHost,
}: let
  verify = extra: {
    othrys.system.autoUpgrade = {
      enable = true;
      verify = {
        enable = true;
        url = "https://example.com/alice/hosts.git";
        publicKeys = ["/run/signers/alice.asc"];
      };
      inherit (extra) flags;
    };
  };
  host = hostConfig [functioningHost (verify {flags = [];})];
  notifying = hostConfig [
    functioningHost
    (verify {flags = [];})
    {
      othrys.services.notify = {
        enable = true;
        url = "https://ntfy.example.com";
        topic = "alerts";
        tokenFile = "/run/secrets/ntfy/token";
      };
    }
  ];
  refuses = flag: rejectedWith "flags must not contain" (hostConfig [functioningHost (verify {flags = [flag];})]);
  unit = h: h.systemd.services.othrys-auto-upgrade-verify;
in
  mkExpectations "othrys-eval-auto-upgrade" {
    "maxAge defaults to thirty days" = host.othrys.system.autoUpgrade.verify.maxAge == 30;
    "--override-flake is refused" = refuses "--override-flake nixpkgs github:example/nixpkgs";
    "--option is refused" = refuses "--option substituters https://example.com";
    "--impure is refused" = refuses "--impure";
    "the verify unit stages the notify token" = (unit notifying).serviceConfig.LoadCredential == ["token:/run/secrets/ntfy/token"];
    "the verify unit stages nothing without notify" = !((unit host).serviceConfig ? LoadCredential);
    "the verify unit runs in its own user namespace and keeps its network" = (unit host).serviceConfig.PrivateUsers && !((unit host).serviceConfig ? IPAddressDeny);
  }
