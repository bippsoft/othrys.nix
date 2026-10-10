# flake/checks/headscale.nix
# EXTENDED. Control-plane handshake between a headscale server and a tailscale
# client (both othrys modules) on a virtual network, where the client
# registers through the module's own baseURL and authKeyFile and lands on the
# tailnet with a CGNAT address. Proves the two modules interoperate through
# their options, with no hand-run `tailscale up`.
{
  pkgs,
  inputs,
}: let
  testStubs = {lib, ...}: {
    imports = [
      inputs.self.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
      inputs.disko.nixosModules.disko
      inputs.impermanence.nixosModules.impermanence
      inputs.sops-nix.nixosModules.sops
      {
        options.stylix = lib.mkOption {
          type = lib.types.attrs;
          default = {};
        };
      }
    ];
  };
in
  pkgs.testers.runNixOSTest {
    name = "othrys-headscale-tailscale";
    node.specialArgs = {inherit inputs;};

    nodes = {
      server = {
        imports = [testStubs];
        environment.systemPackages = [pkgs.jq];
        othrys.services.headscale = {
          enable = true;
          serverUrl = "http://server:8080";
          address = "0.0.0.0";
          magicDns = false;
          openFirewall = true;
          # No DNS meddling inside the test network, and no remote
          # DERP-map fetch (the VM has no internet). Headscale refuses
          # an empty DERP map, so serve an embedded region instead.
          settings = {
            dns.override_local_dns = false;
            derp = {
              urls = [];
              paths = [];
              server = {
                enabled = true;
                region_id = 999;
                region_code = "test";
                region_name = "test";
                stun_listen_addr = "0.0.0.0:3478";
              };
            };
          };
        };
      };

      client = {
        imports = [testStubs];
        othrys.services.tailscale = {
          enable = true;
          baseURL = "http://server:8080";
          # Minted on the server during the test and written here, after
          # which the registration unit is started again.
          authKeyFile = "/run/tailscale-auth-key";
          acceptDns = false;
        };
      };
    };

    testScript = ''
      start_all()
      server.wait_for_unit("headscale.service")
      server.wait_for_open_port(8080)
      client.wait_for_unit("tailscaled.service")

      with subtest("the registration unit carries the login server and the key file"):
          # The unit's ExecStart is a generated script; the flags are in it.
          script = client.succeed(
              "systemctl show -p ExecStart --value tailscaled-autoconnect.service | grep -o '/nix/store/[^ ;]*' | head -1"
          ).strip()
          up = client.succeed(f"cat {script}")
          assert "--login-server=http://server:8080" in up, up
          assert "/run/tailscale-auth-key" in up, up

      with subtest("a preauth key minted on the server registers the client through the module"):
          server.succeed("headscale users create test")
          user_id = server.succeed(
              "headscale users list -o json | jq -r '.[0].id'"
          ).strip()
          key = server.succeed(
              f"headscale preauthkeys create --user {user_id} --expiration 1h -o json | jq -r '.key'"
          ).strip()
          client.succeed(f"install -m 0600 /dev/null /run/tailscale-auth-key && echo -n {key} > /run/tailscale-auth-key")
          client.succeed("systemctl restart tailscaled-autoconnect.service")

      with subtest("the client is on the tailnet"):
          client.succeed("tailscale ip -4 | grep -E '^100\\.'")
          server.succeed("headscale nodes list | grep client")

      with subtest("the set flags reached the daemon"):
          # A oneshot that ran at boot, before the node was registered; run
          # it again now so the flags are applied to a logged-in daemon.
          client.succeed("systemctl start tailscaled-set.service")
          prefs = client.succeed("tailscale debug prefs")
          assert '"CorpDNS": false' in prefs, prefs
          assert '"RouteAll": false' in prefs, prefs
    '';
  }
