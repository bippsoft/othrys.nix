# flake/checks/keyring.nix
# EXTENDED. Two booted machines, one for each way out of the keyring's
# password prompt, where a secret is stored and read back through the Secret
# Service with nobody at a prompt. The evaluation check compares what the
# module writes. This one shows that gnome-keyring takes the keyring file the
# module creates as a store without a password, and that pass-secret-service
# encrypts to the key its store names. No graphical session is started, so a
# request that needed a prompt would have nothing to draw it and fails here.
{
  pkgs,
  inputs,
}: let
  # A placeholder in the shape of a fingerprint. The OpenPGP key is generated
  # inside the machine, so its fingerprint is not known when the module is
  # evaluated. The module initialises the store for the placeholder, and the
  # test then names the generated key in `.gpg-id`, as the owner of a store
  # does when changing its key.
  placeholder = "0123456789ABCDEF0123456789ABCDEF01234567";

  base = {
    imports = [
      inputs.self.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
      inputs.impermanence.nixosModules.impermanence
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
  };
in
  pkgs.testers.runNixOSTest {
    name = "othrys-keyring";

    # Modules still need `inputs` (some dereference inputs.* in gated code).
    node.specialArgs = {inherit inputs;};

    nodes.passwordless = {
      imports = [base];

      # No compositor is enabled, so the keyring is switched on by name. A
      # test machine has no LUKS device, which the module would refuse.
      othrys.desktop.keyring = {
        enable = true;
        passwordless = true;
        allowUnencryptedDisk = true;
      };

      environment.systemPackages = [pkgs.libsecret];
    };

    nodes.openpgp = {
      imports = [base];

      othrys.desktop.keyring = {
        enable = true;
        provider = "pass";
        pass.gpgKey = placeholder;
      };

      environment.systemPackages = [pkgs.libsecret pkgs.gnupg];
    };

    testScript = ''
      secret = "correct-horse-battery-staple"
      label = "othrys-keyring-test"


      def start_session(node):
          # A lingering user gets a service manager and a session bus without
          # anybody logging in.
          node.succeed("loginctl enable-linger alice")
          uid = node.succeed("id -u alice").strip()
          node.wait_for_unit(f"user@{uid}.service")
          node.wait_for_file(f"/run/user/{uid}/bus")


      def session(node, command):
          uid = node.succeed("id -u alice").strip()
          env = f"XDG_RUNTIME_DIR=/run/user/{uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"
          return f"su - alice -c 'export {env}; {command}'"


      def round_trip(node):
          # The timeout turns a request that waits on a prompt into a failure.
          node.succeed(session(node, f"printf %s {secret} | timeout 60 secret-tool store --label={label} service {label}"))
          found = node.succeed(session(node, f"timeout 60 secret-tool lookup service {label}")).strip()
          assert found == secret, f"unexpected secret: {found!r}"


      start_all()

      with subtest("the keyring file is created without a password before the daemon runs"):
          passwordless.wait_for_unit("multi-user.target")
          passwordless.wait_for_unit("home-manager-alice.service")
          keyrings = "/home/alice/.local/share/keyrings"
          keyring = f"{keyrings}/Default_keyring.keyring"
          mode = passwordless.succeed(f"stat -c %a {keyrings}").strip()
          assert mode == "700", f"keyring directory mode is {mode}"
          for path in [keyring, f"{keyrings}/default"]:
              mode = passwordless.succeed(f"stat -c '%U %a' {path}").strip()
              assert mode == "alice 600", f"{path} is {mode}"
          assert "[keyring]" in passwordless.succeed(f"cat {keyring}").splitlines()
          default = passwordless.succeed(f"cat {keyrings}/default").strip()
          assert default == "Default_keyring", f"unexpected default keyring: {default!r}"

      with subtest("gnome-keyring stores and returns a secret with no prompt"):
          start_session(passwordless)
          round_trip(passwordless)
          passwordless.succeed("pgrep -u alice -f gnome-keyring-daemon")

      with subtest("the secret went into the keyring without a password, which stays private"):
          passwordless.wait_until_succeeds(f"grep -q {label} {keyring}", timeout=30)
          mode = passwordless.succeed(f"stat -c '%U %a' {keyring}").strip()
          assert mode == "alice 600", f"{keyring} is {mode}"
          passwordless.fail(f"test -e {keyrings}/login.keyring")

      with subtest("a second activation leaves the keyring and its secret in place"):
          passwordless.succeed("systemctl restart home-manager-alice.service")
          passwordless.succeed(f"grep -q {label} {keyring}")

      with subtest("the password store is initialised for the configured key"):
          openpgp.wait_for_unit("multi-user.target")
          openpgp.wait_for_unit("home-manager-alice.service")
          store = "/home/alice/.local/share/password-store"
          mode = openpgp.succeed(f"stat -c '%U %a' {store}").strip()
          assert mode == "alice 700", f"{store} is {mode}"
          mode = openpgp.succeed(f"stat -c '%U %a' {store}/.gpg-id").strip()
          assert mode == "alice 600", f"{store}/.gpg-id is {mode}"
          named = openpgp.succeed(f"cat {store}/.gpg-id").strip()
          assert named == "${placeholder}", f"unexpected key in .gpg-id: {named!r}"

      with subtest("a software key with no passphrase stands in for the token"):
          start_session(openpgp)
          openpgp.succeed(session(openpgp, "gpg --batch --pinentry-mode loopback --passphrase \"\" --quick-generate-key alice@example.com"))
          listing = openpgp.succeed(session(openpgp, "gpg --batch --with-colons --list-keys alice@example.com"))
          fingerprint = [line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:")][0]
          assert len(fingerprint) >= 40, f"unexpected fingerprint: {fingerprint!r}"
          # Written over the file in place, which keeps its owner and mode.
          openpgp.succeed(f"echo {fingerprint} > {store}/.gpg-id")
          openpgp.succeed("systemctl restart home-manager-alice.service")
          named = openpgp.succeed(f"cat {store}/.gpg-id").strip()
          assert named == fingerprint, f"activation replaced .gpg-id with {named!r}"

      with subtest("pass-secret-service is the only provider"):
          openpgp.succeed(session(openpgp, "systemctl --user restart pass-secret-service.service"))
          openpgp.succeed(session(openpgp, "systemctl --user is-active pass-secret-service.service"))
          openpgp.fail("test -e /run/wrappers/bin/gnome-keyring-daemon")

      with subtest("pass stores and returns a secret, encrypted to the key"):
          round_trip(openpgp)
          encrypted = openpgp.succeed(f"find {store} -name '*.gpg'").split()
          assert encrypted, "the store holds no encrypted file"
          openpgp.fail(f"grep -r {secret} {store}")
    '';
  }
