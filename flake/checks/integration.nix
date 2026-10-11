# flake/checks/integration.nix
# EXTENDED. Structured integration test that boots a real machine built from
# nixosModules.default with a representative set of modules enabled, and
# assert runtime behavior (user creation, home-manager activation,
# services listening) rather than just evaluation. Identity comes from
# the othrys.system.user.name option, with no `username` specialArg.
{
  pkgs,
  inputs,
}:
pkgs.testers.runNixOSTest {
  name = "othrys-integration";

  # Modules still need `inputs` (some dereference inputs.* in gated code).
  node.specialArgs = {inherit inputs;};

  nodes.machine = {pkgs, ...}: {
    imports = [
      inputs.self.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
    ];

    virtualisation.memorySize = 2048;

    # The test framework sets nixpkgs.pkgs, so we can't also enable
    # othrys.system.nix (it sets nixpkgs.config). Its eval is covered by
    # eval-default, so here we set the state versions it would provide.
    system.stateVersion = "26.05";
    home-manager.users.alice.home.stateVersion = "26.05";

    othrys.system.user.name = "alice";
    othrys.system.users = {
      enable = true;
      # Bootstrap hash for "test", generated with mkpasswd -m yescrypt.
      initialHashedPassword = "$y$j9T$Z7b2.WMjThgzBelkR7Y4e.$1ujsmGNTPfFJODKtqFoneFmQXMuhH3kv8xVQaP0BK93";
      defaultShell = pkgs.zsh;
    };
    othrys.system.git = {
      enable = true;
      name = "Alice Example";
      email = "alice@example.com";
    };
    othrys.system.shell.zsh.enable = true;
    # A second port beside 22, so sshd and the fail2ban jail each have to
    # follow the configured list for the subtests below to pass.
    othrys.services.ssh = {
      enable = true;
      server = {
        enable = true;
        ports = [22 2222];
      };
    };
    othrys.services.security.fail2ban.enable = true;
    othrys.services.firewall.enable = true;
    othrys.services.monitoring.enable = true;

    # The two units below run under the shared sandbox baseline, so they are
    # started here to show the baseline leaves them working.
    othrys.services.docs.enable = true;
    environment.etc."ntfy-token".text = "tk_integrationtest";
    othrys.services.notify = {
      enable = true;
      url = "http://127.0.0.1:2586";
      topic = "alerts";
      tokenFile = "/etc/ntfy-token";
    };
    othrys.services.alerting.enable = true;
  };

  testScript = {nodes, ...}: ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("primary user exists in wheel with a zsh login shell"):
        machine.succeed("id alice")
        machine.succeed("id -nG alice | grep -qw wheel")
        shell = machine.succeed("getent passwd alice | cut -d: -f7").strip()
        assert "zsh" in shell, f"expected a zsh login shell, got {shell!r}"

    with subtest("home-manager activated and applied the git identity"):
        machine.wait_for_unit("home-manager-alice.service")
        email = machine.succeed(
            "su - alice -c 'git config --get user.email'"
        ).strip()
        assert email == "alice@example.com", f"unexpected git email: {email!r}"

    with subtest("essential home-manager CLI tools are on the user PATH"):
        machine.succeed("su - alice -c 'command -v jq'")
        machine.succeed("su - alice -c 'command -v just'")
        machine.succeed("su - alice -c 'command -v tree'")

    with subtest("ssh server is reachable on port 22"):
        machine.wait_for_open_port(22)

    with subtest("sshd runs with the configured ports and the hardened defaults"):
        machine.wait_for_open_port(2222)
        # sshd -T prints the configuration the daemon resolves, one directive
        # per line, so it shows what sshd applies and not only what the module
        # wrote. The keyword case differs between OpenSSH releases, so the
        # lines are compared in lower case.
        effective = machine.succeed(
            "${nodes.machine.services.openssh.package}/bin/sshd -T -f /etc/ssh/sshd_config"
        ).lower().splitlines()
        for line in [
            "port 22",
            "port 2222",
            "maxauthtries 3",
            "logingracetime 30",
            "allowtcpforwarding no",
            "allowagentforwarding no",
            "passwordauthentication no",
            "permitrootlogin no",
            "kexalgorithms sntrup761x25519-sha512@openssh.com,mlkem768x25519-sha256,curve25519-sha256,curve25519-sha256@libssh.org",
        ]:
            assert line in effective, f"sshd -T does not report {line!r}"

    with subtest("the fail2ban sshd jail names the configured ports"):
        machine.wait_for_unit("fail2ban.service")
        # The unit is active before the server answers on its socket.
        machine.wait_until_succeeds("fail2ban-client status sshd", timeout=60)
        # The [sshd] section of the rendered jail file, up to the next section.
        jail = machine.succeed("sed -n '/^\\[sshd\\]/,/^\\[/p' /etc/fail2ban/jail.local")
        assert "port = 22,2222" in jail.splitlines(), f"unexpected sshd jail: {jail!r}"

    with subtest("base firewall is active"):
        machine.wait_for_unit("firewall.service")
        machine.succeed("systemctl is-active firewall.service")

    with subtest("prometheus monitoring stack is serving"):
        machine.wait_for_unit("prometheus.service")
        machine.wait_for_unit("prometheus-node-exporter.service")
        machine.wait_for_open_port(9090)
        machine.wait_for_open_port(9100)

    with subtest("the sandboxed docs server still serves"):
        machine.wait_for_unit("othrys-docs.service")
        machine.wait_for_open_port(3000)
        # Saved to a file first. grep -q leaves at the first match, and curl
        # still writing into the closed pipe would fail the pipeline.
        machine.succeed("curl -fsS -o /tmp/docs-index.html http://127.0.0.1:3000/")
        machine.succeed("grep -qi '<html' /tmp/docs-index.html")

    with subtest("the sandboxed render unit writes the bridge auth file"):
        machine.wait_for_unit("othrys-alerting-ntfy-auth.service")
        machine.succeed("grep -q 'token: \"tk_integrationtest\"' /run/othrys-alerting/ntfy-auth.yml")
        mode = machine.succeed("stat -c %a /run/othrys-alerting/ntfy-auth.yml").strip()
        assert mode == "600", f"auth file mode is {mode}"
        machine.wait_for_unit("alertmanager-ntfy.service")

    with subtest("a token that would break the YAML fails the render unit"):
        machine.succeed("cp /etc/ntfy-token /root/token.bak")
        machine.succeed("rm /etc/ntfy-token && printf 'tk_a\"b' > /etc/ntfy-token")
        machine.fail("systemctl restart othrys-alerting-ntfy-auth.service")
        machine.succeed("rm /etc/ntfy-token")
        machine.fail("systemctl restart othrys-alerting-ntfy-auth.service")
  '';
}
