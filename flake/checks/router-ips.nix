# flake/checks/router-ips.nix
# EXTENDED. Runtime proof for the inline IPS path, on the topology in
# ./lib/router-topology.nix with the router's NFQUEUE hook on and the Suricata
# module bound to the queue. One local rule drops HTTP requests whose URI
# carries a marker. The test shows the rule dropping, then stops Suricata and
# shows forwarded traffic still passing, which is the `bypass` verdict the
# router documents and the reason this test exists.
{
  pkgs,
  inputs,
}: let
  sid = 1000001;
  marker = "othrys-ips-drop-marker";
  extraRules = "/var/lib/suricata-extra/extra.rules";

  localRules = pkgs.writeText "local.rules" ''
    drop http any any -> any any (msg:"othrys router-ips-test marker"; flow:to_server,established; http.uri; content:"${marker}"; sid:${toString sid}; rev:1;)
  '';

  topology = import ./lib/router-topology.nix {
    inherit pkgs inputs;
    routerModule = {
      virtualisation.memorySize = 1024;

      othrys.services.router.suricata.enable = true;

      systemd.tmpfiles.rules = [
        "d ${builtins.dirOf extraRules} 0755 root root -"
        "f ${extraRules} 0644 root root -"
      ];

      # The failure hook needs a notify target to exist. Nothing listens
      # there, and the subtest only checks that the hook was triggered.
      othrys.services.notify = {
        enable = true;
        url = "http://127.0.0.1:2586";
        topic = "router";
      };

      # The module waits thirty seconds between attempts. One second keeps the
      # five attempts that lead to `failed` inside the test's time budget.
      systemd.services.suricata.serviceConfig.RestartSec = pkgs.lib.mkForce "1s";

      othrys.services.suricata = {
        enable = true;
        posture = "ips";
        # The sandbox has no network to fetch a ruleset from, so the only rule
        # loaded is the local one and the classification table comes from the
        # package instead of from suricata-update.
        enabledSources = [];
        offloadInterfaces = ["eth1" "eth2" "eth3"];
        settings = {
          # The second file starts empty and is writable, so a subtest can
          # plant a rule that cannot load and take it away again.
          rule-files = ["${localRules}" extraRules];
          classification-file = "${pkgs.suricata}/etc/suricata/classification.config";
          outputs = [
            {
              fast = {
                enabled = true;
                filename = "fast.log";
                append = true;
              };
            }
          ];
        };
      };
    };
  };
  inherit (topology) net ports;
in
  pkgs.testers.runNixOSTest {
    name = "othrys-router-ips";
    node.specialArgs = {inherit inputs;};

    inherit (topology) nodes;

    testScript = ''
      wan_url = "http://${net.wan.host}:${toString ports.wan}/"
      marker_url = wan_url + "${marker}"
      queues = "/proc/net/netfilter/nfnetlink_queue"

      ${topology.scriptHelpers}

      def wait_for_suricata(engine_starts):
          # The unit is active as soon as the process forks. Packets are only
          # inspected once the engine has loaded its rules and bound queue 0.
          router.wait_for_unit("suricata.service")
          router.wait_until_succeeds(
              f"test $(journalctl -u suricata.service | grep -c 'Engine started') -ge {engine_starts}",
              timeout=120,
          )
          router.wait_until_succeeds(f"grep -q '^ *0 ' {queues}")


      def drops():
          count = router.succeed(
              "grep -c '\\[Drop\\].*\\[1:${toString sid}:' /var/log/suricata/fast.log || true"
          )
          return int(count)


      start_all()
      router.wait_for_unit("nftables.service")
      router.wait_for_unit("kea-dhcp4-server.service")
      wan.wait_for_open_port(${toString ports.wan})
      lanA.wait_until_succeeds("ip route show default | grep -q 'via ${net.lanA.router}'")
      wait_for_suricata(1)
      router.succeed("nft list chain inet router-filter forward | grep -q 'queue.*bypass'")

      with subtest("the sandboxed offload unit still turns the offloads off"):
          result = router.succeed("systemctl show -p Result --value suricata-disable-offload.service").strip()
          assert result == "success", f"the offload unit ended with {result}"
          for iface in ["eth1", "eth2", "eth3"]:
              features = router.succeed(f"${pkgs.ethtool}/bin/ethtool -k {iface}")
              assert "generic-receive-offload: off" in features, f"{iface} still has GRO on"

      with subtest("an ordinary request passes through a running Suricata"):
          assert fetch(lanA, wan_url) == "wan"

      with subtest("the drop rule blocks the marked request and logs its sid"):
          assert_dropped(lanA, marker_url)
          assert drops() >= 1, "fast.log holds no drop for sid ${toString sid}"
          wan.fail("grep -q ${marker} ${topology.wanLog}")

      with subtest("forwarding fails open while Suricata is stopped"):
          router.succeed("systemctl stop suricata.service")
          router.wait_until_fails(f"grep -q '^ *0 ' {queues}")
          assert fetch(lanA, wan_url) == "wan"
          # Uninspected means exactly that, so the marked request gets through
          # as well and the WAN host answers it with a 404.
          lanA.succeed(f"curl -s -o /dev/null --max-time 5 {marker_url}")

      with subtest("the drop rule blocks again once Suricata is back"):
          before = drops()
          router.succeed("systemctl start suricata.service")
          wait_for_suricata(2)
          assert fetch(lanA, wan_url) == "wan"
          assert_dropped(lanA, marker_url)
          assert drops() > before, "the restarted engine logged no new drop"

      with subtest("a rule that cannot load ends in a failed unit, not an endless loop"):
          router.succeed("echo 'alert modbus any any -> any any (msg:\"cannot load\"; sid:1000099;)' > ${extraRules}")
          router.succeed("systemctl restart --no-block suricata.service")
          router.wait_until_succeeds("systemctl is-failed --quiet suricata.service", timeout=180)
          # The limit counts every start in the window, the two earlier in this
          # test included, so only some of the five are retries.
          restarts = int(router.succeed("systemctl show -p NRestarts --value suricata.service").strip())
          assert restarts >= 1, "the unit failed without retrying once"
          router.succeed("journalctl -u suricata.service --no-pager | grep -q 'Start request repeated too quickly'")

      with subtest("the failure is reported and forwarding still passes"):
          router.wait_until_succeeds(
              "journalctl -u 'notify-failure@suricata.service.service' --no-pager | grep -q 'Failure notification for suricata.service'"
          )
          router.wait_until_fails(f"grep -q '^ *0 ' {queues}")
          assert fetch(lanA, wan_url) == "wan"

      with subtest("the recovery unit starts the engine again once the rule is gone"):
          router.succeed(": > ${extraRules}")
          router.succeed("systemctl start suricata-recover.service")
          wait_for_suricata(3)
          assert_dropped(lanA, marker_url)

      with subtest("the recovery unit leaves a running engine alone"):
          pid = router.succeed("systemctl show -p MainPID --value suricata.service").strip()
          router.succeed("systemctl start suricata-recover.service")
          assert pid == router.succeed("systemctl show -p MainPID --value suricata.service").strip()
    '';
  }
