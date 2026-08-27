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
    system.stateVersion = "24.11";
    home-manager.users.alice.home.stateVersion = "24.11";

    othrys.system.user.name = "alice";
    othrys.system.users = {
      enable = true;
      initialPassword = "test";
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
  '';
}
