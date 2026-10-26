# flake/checks/crowdsec.nix
# EXTENDED. Fresh-host proof for the CrowdSec engine + firewall bouncer.
# The module's failure mode is "works on a host that has run it before",
# since a defect in first start stays hidden once /var/lib/crowdsec exists
# and a bouncer is registered. This boots a clean host and asserts every
# unit reaches its target state, then runs the daily hub-update unit,
# which would otherwise fail a day after deployment, and reboots to prove
# the state the first boot produced is state the second boot can use.
{
  pkgs,
  inputs,
}: let
  # crowdsec-setup runs `cscli hub update`, which reaches out to
  # cdn-hub.crowdsec.net, and a test VM has no route there. Serve an empty
  # index locally instead, since hub content is not what this test is about,
  # and collections stay empty.
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
      ];

      virtualisation.memorySize = 2048;
      # Match the deployment this module targets, a router, where the bouncer
      # picks its nftables backend off this flag.
      networking.nftables.enable = true;

      systemd.services.crowdsec-hub-mock = {
        wantedBy = ["multi-user.target"];
        before = ["crowdsec-setup.service"];
        serviceConfig.ExecStart = "${lib.getExe pkgs.darkhttpd} ${hubMock} --port 8000 --addr 127.0.0.1";
      };
      # With no branch set, cscli asks version.crowdsec.net which hub branch
      # matches its release before it fetches anything, and the VM has no
      # route there. Naming the branch the mock serves skips that lookup.
      services.crowdsec.settings.config.cscli = {
        __hub_url_template__ = "http://127.0.0.1:8000/%s/%s";
        hub_branch = "master";
      };

      othrys.services.security.crowdsec = {
        enable = true;
        collections = [];
      };

      # The deployment this module targets is a router, where the bouncer's
      # input-only chains would leave forwarded traffic unfiltered. eth1 is a
      # VLAN of the test driver that stands in for the LAN.
      virtualisation.vlans = [1];
      othrys.services.router = {
        enable = true;
        wan.interface = "eth0";
        lan.interfaces = ["eth1"];
        # The driver reaches the VM over eth0, which is the WAN here.
        extraInputRules = ''iifname "eth0" accept'';
      };
    };

    testScript = ''
      machine.start()
      machine.wait_for_unit("multi-user.target")

      with subtest("every unit reaches its target state on a fresh host"):
          machine.wait_for_unit("crowdsec.service")
          machine.wait_for_unit("crowdsec-firewall-bouncer.service")
          # The setup and register units are oneshots, so "inactive" is their
          # success state.
          for unit in ["crowdsec-setup", "crowdsec-firewall-bouncer-register"]:
              result = machine.succeed(
                  f"systemctl show -p Result --value {unit}.service"
              ).strip()
              assert result == "success", f"{unit} result: {result!r}"
          failed = machine.succeed("systemctl --failed --no-legend").strip()
          assert failed == "", f"failed units: {failed}"

      with subtest("state lives where hosts of the old module kept it"):
          # A symlink here would point into /var/lib/private (0700 root),
          # which locks the engine out of its own hub directory from the
          # second boot on.
          machine.succeed("test -d /var/lib/crowdsec -a ! -L /var/lib/crowdsec")
          owner = machine.succeed("stat -c %U /var/lib/crowdsec/state").strip()
          assert owner == "crowdsec", f"state dir owned by {owner!r}"
          machine.succeed("test -s /var/lib/crowdsec/state/local_api_credentials.yaml")
          machine.succeed("test -s /var/lib/crowdsec/state/crowdsec.db")

      with subtest("cscli works, both through the wrapper and bare"):
          machine.succeed("cscli metrics")
          machine.succeed("test -e /etc/crowdsec/config.yaml")

      with subtest("the bouncer registered with the local engine"):
          machine.succeed("cscli bouncers list -o json | grep -q crowdsec-firewall-bouncer")

      with subtest("on a router a decision lands in a set the forward chain reads"):
          table = machine.succeed("nft list table ip crowdsec")
          assert "hook forward" in table and "@crowdsec-blacklists drop" in table, table
          machine.succeed("cscli decisions add -i 192.0.2.99 -d 1h --reason test")
          machine.wait_until_succeeds("nft list set ip crowdsec crowdsec-blacklists | grep -q 192.0.2.99")

      with subtest("the daily hub-update timer completes and reloads the engine"):
          # autoUpdate is on by default, so this unit runs on every host
          # within a day of deployment, long after anyone is watching.
          machine.succeed("systemctl start crowdsec-update-hub.service")
          machine.succeed("systemctl is-active crowdsec.service")
          failed = machine.succeed("systemctl --failed --no-legend").strip()
          assert failed == "", f"failed units after hub update: {failed}"

      with subtest("the layout the first boot produced survives a reboot"):
          machine.shutdown()
          machine.start()
          machine.wait_for_unit("crowdsec.service")
          machine.wait_for_unit("crowdsec-firewall-bouncer.service")
          failed = machine.succeed("systemctl --failed --no-legend").strip()
          assert failed == "", f"failed units after reboot: {failed}"
    '';
  }
