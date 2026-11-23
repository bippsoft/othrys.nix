# flake/checks/soju.nix
# EXTENDED. soju booted behind Traefik, where a client registers in plaintext
# on loopback and over TLS through Traefik's TCP router. The evaluation check
# compares what the module writes. This one shows that soju starts on the
# listeners it is given, which upstream's TLS-only default does not, that
# Traefik's PROXY header reaches soju as the client's address, and that a
# trusted peer that sends no header is still accepted.
{
  pkgs,
  inputs,
}: let
  # No CA is reachable from a VM, so Traefik is given a self-signed default
  # certificate for the domain while its ACME resolver fails in the
  # background. The client does not verify it.
  certificate = pkgs.runCommand "othrys-soju-test-certificate" {nativeBuildInputs = [pkgs.openssl];} ''
    mkdir "$out"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -subj /CN=irc.example.com -addext subjectAltName=DNS:irc.example.com \
      -keyout "$out/key.pem" -out "$out/cert.pem"
  '';

  password = "alice-test-password";

  # Registers as alice with PASS and waits for 001. With --whois it prints
  # the host soju reports for alice's own connection, which soju takes from
  # the peer address or, for a trusted peer, from the PROXY header.
  client = pkgs.writers.writePython3Bin "soju-test-client" {flakeIgnore = ["E501"];} ''
    import argparse
    import socket
    import ssl
    import sys

    parser = argparse.ArgumentParser()
    parser.add_argument("host")
    parser.add_argument("port", type=int)
    parser.add_argument("--password", required=True)
    parser.add_argument("--tls-name")
    parser.add_argument("--whois", action="store_true")
    args = parser.parse_args()

    transcript = []


    def fail(reason):
        print(reason, file=sys.stderr)
        for line in transcript:
            print(line, file=sys.stderr)
        sys.exit(1)


    def parse(line):
        if line.startswith(":"):
            line = line.partition(" ")[2]
        trailing = None
        if " :" in line:
            line, _, trailing = line.partition(" :")
        params = line.split()
        if trailing is not None:
            params.append(trailing)
        return params[0].upper(), params[1:]


    sock = socket.create_connection((args.host, args.port), timeout=30)
    if args.tls_name:
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        sock = context.wrap_socket(sock, server_hostname=args.tls_name)


    def send(line):
        transcript.append("> " + line)
        sock.sendall(line.encode() + b"\r\n")


    def messages():
        buffer = b""
        while True:
            try:
                chunk = sock.recv(4096)
            except ConnectionResetError:
                return
            if not chunk:
                return
            buffer += chunk
            while b"\n" in buffer:
                raw, buffer = buffer.split(b"\n", 1)
                line = raw.decode(errors="replace").rstrip("\r")
                if line:
                    transcript.append("< " + line)
                    yield parse(line)


    try:
        send("CAP LS 302")
        send("PASS " + args.password)
        send("NICK alice")
        send("USER alice 0 * :alice")
        for command, params in messages():
            if command == "PING":
                send("PONG :" + (params[-1] if params else ""))
            elif command == "CAP" and len(params) >= 2 and params[1] == "LS":
                if not (len(params) >= 4 and params[2] == "*"):
                    send("CAP END")
            elif command == "001":
                if not args.whois:
                    sys.exit(0)
                send("WHOIS alice")
            elif command == "311":
                print(params[3])
                sys.exit(0)
            elif command in ("464", "904", "ERROR"):
                fail("refused")
    except socket.timeout:
        fail("timed out")

    fail("connection closed before the expected reply")
  '';
in
  pkgs.testers.runNixOSTest {
    name = "othrys-soju";

    # Modules still need `inputs` (some dereference inputs.* in gated code).
    node.specialArgs = {inherit inputs;};

    nodes.machine = {
      imports = [inputs.self.nixosModules.default];

      # The test framework sets nixpkgs.pkgs, so othrys.system.nix stays off
      # and the state version it would provide is set here.
      system.stateVersion = "26.05";

      environment.systemPackages = [client];

      # The provider credential the ACME assertion asks for. Nothing reads it
      # successfully, since the VM reaches no DNS provider.
      environment.etc."traefik-env".text = "CF_DNS_API_TOKEN=placeholder\n";

      othrys.services.traefik = {
        enable = true;
        acme = {
          enable = true;
          email = "alice@example.com";
          dnsProvider = "cloudflare";
        };
        environmentFiles = ["/etc/traefik-env"];
        tls.sniStrict = false;
        dynamicConfigOptions.tls.stores.default.defaultCertificate = {
          certFile = "${certificate}/cert.pem";
          keyFile = "${certificate}/key.pem";
        };
      };

      othrys.services.soju = {
        enable = true;
        traefik = {
          enable = true;
          domain = "irc.example.com";
        };
      };
    };

    testScript = ''
      password = "${password}"
      start_all()

      with subtest("soju starts on its plaintext loopback listeners"):
          machine.wait_for_unit("soju.service")
          machine.wait_for_open_port(6667, addr="127.0.0.1")
          listening = machine.succeed("ss -Htln")
          assert "127.0.0.1:6667" in listening, listening
          assert "[::1]:6667" in listening, listening
          # Restart=always would bring a soju that exits on a TLS-only
          # listener back to active between attempts.
          restarts = machine.succeed("systemctl show -p NRestarts --value soju.service").strip()
          assert restarts == "0", f"soju restarted {restarts} times"
          machine.fail("journalctl -u soju.service | grep -F 'missing TLS configuration'")

      with subtest("sojuctl creates alice as an admin"):
          machine.wait_for_file("/run/soju/admin")
          machine.succeed(f"sojuctl user create -username alice -password {password} -admin=true")

      with subtest("alice registers in plaintext on 127.0.0.1"):
          machine.succeed(f"soju-test-client 127.0.0.1 6667 --password {password}")

      with subtest("alice registers over TLS through Traefik"):
          machine.wait_for_unit("traefik.service")
          machine.wait_for_open_port(6697, addr="127.0.0.1")
          # The entrypoint binds before the file provider has loaded the
          # router, so the first attempts may find no route.
          machine.wait_until_succeeds(
              f"soju-test-client 127.0.0.1 6697 --password {password} --tls-name irc.example.com",
              timeout=60,
          )

      with subtest("soju takes alice's address from the PROXY header"):
          host = machine.succeed(
              f"soju-test-client 127.0.0.1 6697 --password {password} --tls-name irc.example.com --whois"
          ).strip()
          assert host == "127.0.0.1", f"soju saw alice at {host!r}, not at the address Traefik read"

      # go-proxyproto's USE policy, which soju gives a trusted peer, takes
      # the header when one is sent and accepts the connection without it.
      with subtest("a trusted peer that sends no PROXY header still registers"):
          machine.succeed(f"soju-test-client ::1 6667 --password {password}")
    '';
  }
