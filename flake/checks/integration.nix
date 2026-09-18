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

  nodes.machine = {
    pkgs,
    lib,
    ...
  }: {
    imports = [
      inputs.self.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
      inputs.disko.nixosModules.disko
      inputs.impermanence.nixosModules.impermanence
      inputs.sops-nix.nixosModules.sops
      # The real Stylix module adds nixpkgs overlays, which clash with the
      # test framework's read-only nixpkgs. Stylix theming is eval-tested
      # in eval-default, and here we only need the `stylix` option namespace to
      # exist so the (disabled) othrys stylix module still type-checks.
      {
        options.stylix = lib.mkOption {
          type = lib.types.attrs;
          default = {};
        };
      }
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
    othrys.services.ssh = {
      enable = true;
      server.enable = true;
    };
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

  testScript = ''
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
