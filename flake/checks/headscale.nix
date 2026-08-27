# flake/checks/headscale.nix
# EXTENDED. Control-plane handshake between a headscale server and a tailscale
# client (both othrys modules) on a virtual network, where the client
# registers with a preauth key and lands on the tailnet with a CGNAT
# address. Proves the two modules actually interoperate, not just eval.
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
          acceptDns = false;
        };
      };
    };

    testScript = ''
      start_all()
      server.wait_for_unit("headscale.service")
      server.wait_for_open_port(8080)
      client.wait_for_unit("tailscaled.service")

      with subtest("preauth key mints and the client registers"):
          server.succeed("headscale users create test")
          user_id = server.succeed(
              "headscale users list -o json | jq -r '.[0].id'"
          ).strip()
          key = server.succeed(
              f"headscale preauthkeys create --user {user_id} --expiration 1h -o json | jq -r '.key'"
          ).strip()
          client.succeed(
              f"tailscale up --login-server http://server:8080 --auth-key {key} "
              "--accept-dns=false --timeout 60s"
          )

      with subtest("the client is on the tailnet"):
          client.succeed("tailscale ip -4 | grep -E '^100\\.'")
          server.succeed("headscale nodes list | grep client")
    '';
  }
