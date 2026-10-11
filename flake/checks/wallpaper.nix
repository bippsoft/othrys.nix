# flake/checks/wallpaper.nix
# EXTENDED. A booted machine with a compositor module and a list of two
# wallpapers, where the files the wallpaper daemon will read are looked at on
# disk. The evaluation check compares the configuration as Nix values. This
# one shows that Home Manager installed the unit into the graphical session,
# that the rendered file names the directory and the interval, and that the
# directory built from the list holds both images under names the daemon
# takes for images. No graphical session is started, so the daemon itself
# does not run here.
{
  pkgs,
  inputs,
}: let
  # Two images small enough to build in a moment, each named with the
  # extension the daemon tells an image by.
  image = name: colour:
    pkgs.runCommand "${name}.png" {
      nativeBuildInputs = [pkgs.imagemagick];
    } ''
      magick -size 16x16 "xc:${colour}" "png:$out"
    '';
  dawn = image "dawn" "#aa5502";
  dusk = image "dusk" "#0000a6";
in
  pkgs.testers.runNixOSTest {
    name = "othrys-wallpaper";

    # Modules still need `inputs` (some dereference inputs.* in gated code).
    node.specialArgs = {inherit inputs;};

    nodes.machine = {
      imports = [
        inputs.self.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
      ];

      virtualisation.memorySize = 2048;

      # The test framework sets nixpkgs.pkgs, so othrys.system.nix stays off
      # and the state versions it would provide are set here.
      system.stateVersion = "26.05";
      home-manager.users.alice.home.stateVersion = "26.05";

      othrys.system.user.name = "alice";
      othrys.system.users = {
        enable = true;
        # Bootstrap hash for "test", generated with mkpasswd -m yescrypt.
        initialHashedPassword = "$y$j9T$Z7b2.WMjThgzBelkR7Y4e.$1ujsmGNTPfFJODKtqFoneFmQXMuhH3kv8xVQaP0BK93";
      };

      # niri comes from nixpkgs, which keeps the closure of this test to
      # packages the binary cache already holds.
      othrys.desktop.compositors.niri.enable = true;
      othrys.theme.wallpaper = {
        source = [dawn dusk];
        interval = "10m";
      };
    };

    testScript = {nodes, ...}: let
      directory = nodes.machine.home-manager.users.alice.services.wpaperd.settings.any.path;
    in ''
      machine.start()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("home-manager-alice.service")

      units = "/home/alice/.config/systemd/user"
      config = "/home/alice/.config/wpaperd/wallpaper.toml"
      directory = "${directory}"

      with subtest("the daemon's unit is installed and wanted by the graphical session"):
          machine.succeed(f"test -f {units}/wpaperd.service")
          machine.succeed(f"test -e {units}/graphical-session.target.wants/wpaperd.service")
          unit = machine.succeed(f"cat {units}/wpaperd.service")
          assert "WantedBy=graphical-session.target" in unit, f"unexpected unit: {unit!r}"
          assert "PartOf=graphical-session.target" in unit, f"unexpected unit: {unit!r}"
          assert "/bin/wpaperd" in unit, f"unexpected unit: {unit!r}"

      with subtest("the rendered configuration names the directory and the interval"):
          rendered = machine.succeed(f"cat {config}").splitlines()
          assert "[any]" in rendered, f"no section for every monitor: {rendered!r}"
          assert f'path = "{directory}"' in rendered, f"the directory is missing: {rendered!r}"
          assert 'duration = "10m"' in rendered, f"the interval is missing: {rendered!r}"
          assert 'sorting = "random"' in rendered, f"the order is missing: {rendered!r}"
          assert 'mode = "center"' in rendered, f"the fill is missing: {rendered!r}"

      with subtest("the directory holds both images, in the order of the list"):
          names = machine.succeed(f"ls {directory}").split()
          assert names == ["000-dawn.png", "001-dusk.png"], f"unexpected directory: {names!r}"
          for name, target in [("000-dawn.png", "${dawn}"), ("001-dusk.png", "${dusk}")]:
              machine.succeed(f"cmp {directory}/{name} {target}")
              # The first eight bytes of a PNG file.
              magic = machine.succeed(f"head -c 8 {directory}/{name} | od -An -tx1").split()
              assert magic == ["89", "50", "4e", "47", "0d", "0a", "1a", "0a"], f"{name} is no PNG: {magic!r}"
    '';
  }
