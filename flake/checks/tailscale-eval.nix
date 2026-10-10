# flake/checks/tailscale-eval.nix
# CORE. What the tailscale module hands the daemon, read back from evaluated
# hosts. The control server once went into the auth-key parameters, which
# upstream renders as a query string on the key, and the routing flags went to
# `tailscale up`, which upstream runs only with a key file, so none of it
# reached a host registered by hand. Nothing in that fails evaluation.
{
  hostConfig,
  mkExpectations,
  bootBase,
}: let
  host = extra:
    hostConfig [
      bootBase
      {
        othrys.system.nix = {
          enable = true;
          stateVersion = "26.05";
        };
        othrys.services.tailscale.enable = true;
      }
      extra
    ];

  plain = host {};
  headscale = host {othrys.services.tailscale.baseURL = "https://hs.example.com";};
  keyed = host {
    othrys.services.tailscale = {
      baseURL = "https://hs.example.com";
      authKeyFile = "/run/secrets/tailscale-key";
      acceptRoutes = true;
      ssh = true;
      operator = "alice";
    };
  };
  ts = cfg: cfg.services.tailscale;
  warnsAbout = needle: cfg: builtins.any (w: builtins.match ".*${needle}.*" w != null) cfg.warnings;
in
  mkExpectations "othrys-eval-tailscale" {
    "no login server is passed without one" = (ts plain).extraUpFlags == [];
    "the control server is passed as --login-server" = (ts keyed).extraUpFlags == ["--login-server=https://hs.example.com"];
    "the control server is not a key parameter" = (ts keyed).authKeyParameters.baseURL == null;
    "a key for a control server of its own carries no parameters" = (ts keyed).authKeyParameters.preauthorized == null && (ts keyed).authKeyParameters.ephemeral == null;
    "a key for the public control plane is marked preauthorized" = (ts (host {othrys.services.tailscale.authKeyFile = "/run/secrets/tailscale-key";})).authKeyParameters.preauthorized == true;
    "a control server with no key file warns" = warnsAbout "authKeyFile is not" headscale;
    "a control server with a key file does not warn" = !warnsAbout "authKeyFile is not" keyed;
    "routes are not accepted by default" = builtins.elem "--accept-routes=false" (ts plain).extraSetFlags;
    "the set flags carry routes, DNS, SSH and the operator" = (ts keyed).extraSetFlags == ["--accept-routes=true" "--accept-dns=true" "--ssh=true" "--operator=alice"];
    "no operator is passed by default" = !builtins.any (f: builtins.match "--operator=.*" f != null) (ts plain).extraSetFlags;
  }
