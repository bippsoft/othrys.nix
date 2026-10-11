# flake/checks/listeners.nix
# EXTENDED. The sockets a server listens on and the firewall rules that
# accept traffic, compared with two lists written out below. A module that
# binds a new port, a listener that moves from loopback to every interface
# and an openFirewall default that flips all change what a host exposes, and
# none of them fails an evaluation or a test of the service itself. Here each
# one is a difference from the list, and the test fails until the list is
# updated in the same change.
{
  pkgs,
  inputs,
}:
pkgs.testers.runNixOSTest {
  name = "othrys-listeners";
  node.specialArgs = {inherit inputs;};

  nodes.machine = {
    imports = [
      inputs.self.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
    ];

    # Two metrics stores, a log store and Grafana run side by side.
    virtualisation.memorySize = 4096;

    # The test framework sets nixpkgs.pkgs, so othrys.system.nix stays off
    # and the state version it would provide is set here.
    system.stateVersion = "26.05";

    # The network-facing part of the serverModules fixture in ./default.nix,
    # with every listen address, port and openFirewall option left at its
    # default, since the defaults are what the lists below pin. ntfy is the
    # one difference. The fixture moves it to 0.0.0.0 to exercise an option
    # priority, and here it keeps its loopback default.
    #
    # Left out, because none of them can start in a VM with no network
    # beyond itself:
    # - tailscale stays logged out without a coordination server.
    # - headscale needs a DERP map and is booted in ./headscale.nix.
    # - ddns needs a provider and its credential.
    # - restic needs a repository, and ./restic.nix runs it against a local one.
    # - Traefik's ACME resolver needs a DNS provider and its token, so the
    #   proxy runs here without one.
    # Docker, SMART monitoring and the unattended upgrade open no socket of
    # their own and are left out as well.
    othrys.services = {
      firewall.enable = true;
      ssh = {
        enable = true;
        server.enable = true;
      };
      security.fail2ban.enable = true;
      unbound.enable = true;
      monitoring.enable = true;
      victoriametrics.enable = true;
      victorialogs.enable = true;
      grafana = {
        enable = true;
        secretKeyFile = "/run/test-secrets/grafana-secret-key";
        adminPasswordFile = "/run/test-secrets/grafana-admin-password";
      };
      ntfy.enable = true;
      notify = {
        enable = true;
        tokenFile = "/run/test-secrets/ntfy-token";
      };
      alerting.enable = true;
      docs.enable = true;
      traefik.enable = true;
      wireguard = {
        enable = true;
        interfaces.wg0 = {
          privateKeyFile = "/run/test-secrets/wg0-key";
          ips = ["10.100.0.2/24"];
          listenPort = 51820;
          openFirewall = true;
          peers = [
            {
              publicKey = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=";
              allowedIPs = ["10.100.0.0/24"];
            }
          ];
        };
      };
    };

    # Stand-ins for what a secrets provider would install. Grafana reads its
    # two files as the grafana user, and the notify token is read by root.
    systemd.tmpfiles.rules = [
      "d /run/test-secrets 0755 root root -"
      "f /run/test-secrets/grafana-secret-key 0400 grafana grafana - listenerstestsecretkey"
      "f /run/test-secrets/grafana-admin-password 0400 grafana grafana - listenerstestpassword"
      "f /run/test-secrets/ntfy-token 0400 root root - tk_listenerstest"
    ];
    # The interface key is generated on first start, so no key is written
    # into this file.
    networking.wireguard.interfaces.wg0.generatePrivateKeyFile = true;
  };

  testScript = ''
    import re
    import time

    # One socket per line, as "protocol address:port" in the spelling of the
    # Local Address column of ss, then the service that owns it. An address
    # of * is a socket bound to every address of both families.
    expected_sockets = """
        tcp 0.0.0.0:22       # sshd
        tcp [::]:22          # sshd
        udp 127.0.0.1:53     # unbound
        tcp 127.0.0.1:53     # unbound
        udp [::1]:53         # unbound
        tcp [::1]:53         # unbound
        tcp 127.0.0.1:9090   # prometheus
        tcp 127.0.0.1:9100   # prometheus node exporter
        tcp 127.0.0.1:8428   # victoriametrics
        tcp 127.0.0.1:9428   # victorialogs
        tcp 127.0.0.1:3001   # grafana
        tcp 127.0.0.1:2586   # ntfy
        tcp 127.0.0.1:8880   # vmalert
        tcp 127.0.0.1:9093   # alertmanager
        tcp 127.0.0.1:8489   # alertmanager-ntfy bridge
        tcp 127.0.0.1:3000   # docs server
        tcp *:80             # traefik web entrypoint
        tcp *:443            # traefik websecure entrypoint
        udp 0.0.0.0:51820    # wireguard wg0, held by the kernel
        udp [::]:51820       # wireguard wg0, held by the kernel
        udp 0.0.0.0:68       # dhcpcd, the DHCP client NixOS starts by default
    """

    # Sockets the test VM adds beside the host's own. There are none. The
    # test driver reaches the guest through a shell on the virtio console
    # (backdoor.service), which opens no network socket. A socket that only
    # exists because this is a test VM goes here, in the same format, and
    # nothing is ignored by pattern.
    vm_sockets = """
    """

    # Every accept rule of the nixos-fw chain, which is where the NixOS
    # firewall decides what reaches the host, as "family rule". The rule is
    # what iptables -S prints between the chain and the jump, less the
    # "-m tcp" or "-m udp" match it repeats after the protocol. The
    # connection tracking rule and the ICMP rules name no port and no
    # interface and are the only ones left out.
    expected_rules = """
        ip -i lo                              # loopback, trusted by the firewall's default
        ip -p tcp --dport 22                  # ssh.server.openFirewall, on by default
        ip -p tcp --dport 80                  # traefik.openFirewall, on by default
        ip -p tcp --dport 443                 # traefik.openFirewall, on by default
        ip -p udp --dport 51820               # wireguard wg0, openFirewall set above
        ip6 -i lo                             # loopback
        ip6 -p tcp --dport 22                 # ssh.server.openFirewall
        ip6 -p tcp --dport 80                 # traefik.openFirewall
        ip6 -p tcp --dport 443                # traefik.openFirewall
        ip6 -p udp --dport 51820              # wireguard wg0
        ip6 -d fe80::/64 -p udp --dport 546   # DHCPv6 replies, opened by the NixOS firewall itself
    """


    def parse(block: str) -> dict[str, str]:
        entries: dict[str, str] = {}
        for line in block.splitlines():
            entry, _, note = line.partition("#")
            if entry.strip():
                entries[" ".join(entry.split())] = note.strip()
        return entries


    def render(entries: dict[str, str]) -> str:
        width = max((len(entry) for entry in entries), default=0)
        return "\n".join(
            f"    {entry.ljust(width)}   # {note}" for entry, note in sorted(entries.items())
        )


    def sockets() -> dict[str, str]:
        owners: dict[str, set[str]] = {}
        for line in machine.succeed("ss -H -ltnup").splitlines():
            fields = line.split()
            if len(fields) < 5:
                continue
            names = set(re.findall(r'\("([^"]+)"', line)) or {"no process, held by the kernel"}
            owners.setdefault(f"{fields[0]} {fields[4]}", set()).update(names)
        ignored = parse(vm_sockets)
        return {
            socket: ", ".join(sorted(names))
            for socket, names in owners.items()
            if socket not in ignored
        }


    def rules() -> dict[str, str]:
        found: dict[str, str] = {}
        for family, tool in (("ip", "iptables"), ("ip6", "ip6tables")):
            for line in machine.succeed(f"{tool} -w -S nixos-fw").splitlines():
                rule = re.fullmatch(r"-A nixos-fw (.+) -j nixos-fw-accept", line.strip())
                if rule is None:
                    continue
                body = re.sub(r"-m (tcp|udp) ", "", rule.group(1))
                if re.match(r"-m conntrack |-p (icmp|icmpv6|ipv6-icmp)( |$)", body):
                    continue
                found[f"{family} {body}"] = "nixos-fw"
        return found


    def compare(what: str, read, block: str) -> None:
        expected = parse(block)
        # A unit is active before its socket is bound, and Grafana migrates
        # its database first, so the set is read until it matches. The last
        # reading is the one reported.
        deadline = time.monotonic() + 180
        while True:
            seen = read()
            if set(seen) == set(expected) or time.monotonic() > deadline:
                break
            time.sleep(3)
        extra = sorted(set(seen) - set(expected))
        missing = sorted(set(expected) - set(seen))
        if not extra and not missing:
            return
        report = [f"the {what} differ from the list in flake/checks/listeners.nix"]
        report += [f"  not in the list: {entry} ({seen[entry]})" for entry in extra]
        report += [f"  in the list and absent: {entry} ({expected[entry]})" for entry in missing]
        report += ["everything observed, in the format of the list:", render(seen)]
        raise AssertionError("\n".join(report))


    machine.start()
    machine.wait_for_unit("multi-user.target")
    for unit in [
        "firewall",
        "sshd",
        "fail2ban",
        "unbound",
        "prometheus",
        "prometheus-node-exporter",
        "victoriametrics",
        "victorialogs",
        "grafana",
        "ntfy-sh",
        "vmalert-othrys",
        "alertmanager",
        "alertmanager-ntfy",
        "othrys-docs",
        "traefik",
        "wireguard-wg0",
    ]:
        machine.wait_for_unit(f"{unit}.service")

    with subtest("the listening sockets are the ones listed"):
        compare("listening sockets", sockets, expected_sockets)

    with subtest("the firewall accepts what is listed and nothing else"):
        compare("firewall accept rules", rules, expected_rules)
  '';
}
