# flake/checks/crowdsec.nix
# EXTENDED. Fresh-host proof for the CrowdSec engine + firewall bouncer.
# The module's whole failure mode is "works on a host that has run it
# before": nixpkgs' units only survive once /var/lib/crowdsec exists and
# a bouncer is already registered, so nothing short of a clean boot
# catches it. This boots one and asserts all three units reach their
# target state, then runs the daily hub-update unit (which fails a day
# after deployment, long after anyone is watching), restores a host from
# the /var/lib/private layout the unpatched module leaves behind, and
# reboots to prove the state the first boot produced is state the second
# boot can still use. See the workarounds (and their upstream issues) in
# modules/services/security/crowdsec.nix.
{
  pkgs,
  inputs,
}: let
  # The engine's ExecStartPre runs `cscli hub update` unconditionally,
  # which reaches out to cdn-hub.crowdsec.net, unavailable in a test VM,
  # and fatal under `set -euo pipefail` (nixpkgs #520206). Serve an empty
  # index locally instead, since hub CONTENT is not what this test is about and
  # collections stay empty and every other option keeps its default.
  hubMock = pkgs.runCommand "crowdsec-hub-mock" {} ''
    mkdir -p $out/master
    cat > $out/master/.index.json <<'EOF'
    {"parsers":{},"postoverflows":{},"scenarios":{},"contexts":{},"appsec-configs":{},"appsec-rules":{},"collections":{}}
    EOF
  '';
in
  pkgs.testers.runNixOSTest {
    name = "othrys-crowdsec";
    node.specialArgs = {inherit inputs;};

    nodes.machine = {lib, ...}: {
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

      virtualisation.memorySize = 2048;
      # Match the deployment this module targets, a router, where the bouncer
      # picks its nftables backend off this flag, which is also what makes
      # the After=nftables.service workaround load-bearing.
      networking.nftables.enable = true;

      systemd.services.crowdsec-hub-mock = {
        wantedBy = ["multi-user.target"];
        before = ["crowdsec.service"];
        serviceConfig.ExecStart = "${lib.getExe pkgs.darkhttpd} ${hubMock} --port 8000 --addr 127.0.0.1";
      };
      services.crowdsec.settings.general.cscli.__hub_url_template__ = "http://127.0.0.1:8000/%s/%s";

      othrys.services.security.crowdsec = {
        enable = true;
        collections = [];
      };
    };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      with subtest("all three units reach their target state on a fresh host"):
          machine.wait_for_unit("crowdsec.service")
          machine.wait_for_unit("crowdsec-firewall-bouncer.service")
          # The register unit is a oneshot, so "inactive" is its success state.
          result = machine.succeed(
              "systemctl show -p Result --value crowdsec-firewall-bouncer-register.service"
          ).strip()
          assert result == "success", f"register unit result: {result!r}"
          failed = machine.succeed("systemctl --failed --no-legend").strip()
          assert failed == "", f"failed units: {failed}"

      with subtest("state stayed on the declared account, not under /var/lib/private"):
          # A DynamicUser state dir would make this a symlink into
          # /var/lib/private (0700 root), which is what locks the engine
          # out of its own hub directory from the second boot onwards.
          machine.succeed("test -d /var/lib/crowdsec -a ! -L /var/lib/crowdsec")
          owner = machine.succeed("stat -c %U /var/lib/crowdsec/state").strip()
          assert owner == "crowdsec", f"state dir owned by {owner!r}"

      with subtest("cscli works, both through the wrapper and bare"):
          machine.succeed("cscli metrics")
          machine.succeed("test -e /etc/crowdsec/config.yaml")

      with subtest("the bouncer registered with the local engine"):
          machine.succeed("cscli bouncers list -o json | grep -q crowdsec-firewall-bouncer")

      with subtest("the daily hub-update timer completes and reloads the engine"):
          # autoUpdate is on by default, so this unit runs on every host
          # within a day of deployment, long after anyone is watching.
          machine.succeed("systemctl start crowdsec-update-hub.service")
          machine.succeed("systemctl is-active crowdsec.service")
          failed = machine.succeed("systemctl --failed --no-legend").strip()
          assert failed == "", f"failed units after hub update: {failed}"

      with subtest("a host already broken by the migration recovers by itself"):
          # Recreate what the unpatched module leaves behind, which is
          # what any host that ran it before this fix is sitting on:
          # /var/lib/crowdsec as a symlink into a root-only
          # /var/lib/private, owned by a transient UID that no longer
          # resolves. Recovery must need nothing but a rebuild, so systemd
          # migrates the directory back out and re-chowns it.
          machine.succeed("systemctl stop crowdsec-firewall-bouncer.service crowdsec.service")
          machine.succeed("mkdir -p /var/lib/private && chmod 0700 /var/lib/private")
          machine.succeed("mv /var/lib/crowdsec /var/lib/private/crowdsec")
          machine.succeed("chown -R 61234:61234 /var/lib/private/crowdsec")
          machine.succeed("ln -s private/crowdsec /var/lib/crowdsec")

          machine.succeed("systemctl start crowdsec.service crowdsec-firewall-bouncer.service")
          machine.succeed("test -d /var/lib/crowdsec -a ! -L /var/lib/crowdsec")
          owner = machine.succeed("stat -c %U /var/lib/crowdsec/state").strip()
          assert owner == "crowdsec", f"state dir still owned by {owner!r} after recovery"
          machine.succeed("cscli metrics")

      with subtest("the layout the first boot produced survives a reboot"):
          machine.shutdown()
          machine.start()
          machine.wait_for_unit("crowdsec.service")
          machine.wait_for_unit("crowdsec-firewall-bouncer.service")
          failed = machine.succeed("systemctl --failed --no-legend").strip()
          assert failed == "", f"failed units after reboot: {failed}"
    '';
  }
