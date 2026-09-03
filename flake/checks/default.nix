# flake/checks/default.nix
# CI/CD validation checks: shared fixtures, the eval checks, and wiring for the heavy checks in this directory
{inputs, ...}: {
  perSystem = {
    system,
    config,
    pkgs,
    ...
  }: let
    # The othrys tree plus the upstream modules a real consumer imports (these
    # declare the disko/home-manager/stylix/sops/impermanence option namespaces
    # othrys modules write into).
    upstreamModules = [
      inputs.self.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
      inputs.disko.nixosModules.disko
      inputs.impermanence.nixosModules.impermanence
      inputs.stylix.nixosModules.stylix
      inputs.sops-nix.nixosModules.sops
    ];

    # A bootable core with NO identity at all, just a bootloader and a root
    # filesystem. othrys.system.user.name stays unset, since it is only read when a
    # per-user feature is active, so anonymous hosts must eval.
    bootCore = {
      boot.loader.grub = {
        enable = true;
        devices = ["nodev"];
      };
      fileSystems."/" = {
        device = "/dev/sda1";
        fsType = "ext4";
      };
    };

    # bootCore plus a named primary user (identity via option, no `username`
    # specialArg). Nothing user-facing beyond the name.
    bootBase = {
      imports = [bootCore];
      othrys.system.user.name = "alice";
    };

    # The server-relevant module surface, everything a headless host plausibly
    # enables. Used by eval-host-server (named, no managed account) and
    # eval-host-anonymous (user.name unset) so per-user state can never leak
    # onto hosts without a managed user (see modules/system/nix.nix).
    serverModules = {
      othrys.services.ssh = {
        enable = true;
        server.enable = true;
      };
      othrys.services.tailscale.enable = true;
      othrys.services.firewall.enable = true;
      othrys.services.monitoring.enable = true;
      othrys.services.victoriametrics.enable = true;
      othrys.services.victorialogs.enable = true;
      othrys.services.grafana = {
        enable = true;
        secretKeyFile = "/run/secrets/grafana-secret-key";
      };
      othrys.services.alerting.enable = true;
      othrys.services.ntfy.enable = true;
      othrys.services.notify.enable = true;
      othrys.hardware.smart.enable = true;
      othrys.services.containerization.docker.enable = true;
      othrys.services.containerization.podman.enable = false; # conflicts with docker
      othrys.services.restic.enable = true;
      othrys.services.traefik.enable = true;
      othrys.services.unbound.enable = true;
      othrys.services.headscale = {
        enable = true;
        serverUrl = "https://headscale.example.com";
        baseDomain = "tailnet.example.net";
        nameservers = ["9.9.9.9"];
      };
      othrys.services.security.fail2ban.enable = true;
      othrys.services.security.sudo.enable = true;
      othrys.services.docs.enable = true;
      othrys.system.secrets.enable = true;
      othrys.system.git = {
        enable = true;
        name = "alice";
        email = "alice@example.com";
      };
      othrys.system.shell.zsh.enable = true;
      othrys.system.autoUpgrade = {
        enable = true;
        flake = "github:example/fleet";
      };
      othrys.services.wireguard = {
        enable = true;
        interfaces.wg0 = {
          privateKeyFile = "/run/secrets/wg0-key";
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
      othrys.services.ddns = {
        enable = true;
        provider = "cloudflare.com";
        hostnames = ["home.example.com"];
        username = "example.com";
        credentialsFile = "/run/secrets/ddns";
      };
    };

    # A named primary account that home-manager does NOT manage. The shape the
    # per-user guard exists for, shared by the two app/desktop fixtures below.
    accountNoHomeManager = {
      imports = [bootBase];
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
      othrys.system.users = {
        enable = true;
        homeManager.enable = false;
        # Bootstrap hash for "changeme", generated with mkpasswd -m yescrypt.
        initialHashedPassword = "$y$j9T$aiZuvauf85ZjB04z3seyG0$OKYG9I1g.vAp5IA48MlGzaVoB15gqWIL.k7lSni8fe8";
      };
    };

    # Every app and desktop module that configures the primary user, minus two
    # sets the module tree declares mutually exclusive. hyprland stands for the
    # compositor pair, with niri covered by eval-host-desktop-niri. ashell,
    # idle and nightLight stand for the shell layer, with noctalia covered by
    # the companion fixture below, since noctalia asserts against all three.
    appDesktopModules = {
      # Prerequisites the modules below assert on, rather than things under
      # test. Several apps refuse to evaluate without theming, a Steam install,
      # a JDK or a secrets provider.
      othrys.system.stylix.enable = true;
      othrys.system.secrets.enable = true;
      othrys.system.nix.allowUnfree = true;
      othrys.desktop.graphical = true;
      othrys.apps.gaming.steam.enable = true;
      othrys.apps.languages.java.enable = true;
      # The GitHub MCP module defaults its sops file to secretFiles.common, which
      # only exists when a consumer declares a secrets input. The fixture has
      # none, so it names a file instead of the default.
      othrys.apps.ai.mcp.github.secret.sopsFile = pkgs.writeText "fixture-secrets.yaml" "";
      # The placeholder above is not a real sops file, and this fixture tests the
      # per-user guard rather than decryption.
      sops.validateSopsFiles = false;

      othrys.apps = {
        ai.claude-code.enable = true;
        ai.mcp.context7.enable = true;
        ai.mcp.github.enable = true;
        ai.mcp.nixos.enable = true;
        ai.ollama.enable = true;
        comma.enable = true;
        gh.enable = true;
        nixvim.enable = true;
        yazi.enable = true;
        discord.enable = true;
        floorp.enable = true;
        gaming.mangohud.enable = true;
        gaming.osu.enable = true;
        gaming.prismlauncher.enable = true;
        gaming.r2modman.enable = true;
        ghostty.enable = true;
        idea.enable = true;
        kitty.enable = true;
        mpv.enable = true;
        obs.enable = true;
        picard.enable = true;
        plexamp.enable = true;
        signal.enable = true;
        vesktop.enable = true;
        vscode.enable = true;
      };
      othrys.desktop = {
        ashell.enable = true;
        compositors.hyprland.enable = true;
        idle.enable = true;
        nightLight.enable = true;
      };
    };

    # bootBase plus the core system modules a functioning workstation host needs
    # (a managed user account, nix settings, git).
    functioningHost = {
      imports = [bootBase];
      othrys.system.users = {
        enable = true;
        # Bootstrap hash for "changeme", generated with mkpasswd -m yescrypt.
        initialHashedPassword = "$y$j9T$aiZuvauf85ZjB04z3seyG0$OKYG9I1g.vAp5IA48MlGzaVoB15gqWIL.k7lSni8fe8";
      };
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
      othrys.system.git = {
        enable = true;
        name = "alice";
        email = "alice@example.com";
      };
    };

    # CONTRIBUTING.md holds the canonical consumer contract, and CLAUDE.md keeps
    # an inline copy because an agent reads that file automatically. Duplication
    # is only dangerous when the copies can disagree unnoticed, so this diffs the
    # two anchored regions and turns the duplicate into an enforced mirror.
    # Run from a repository root.
    contractMirror = pkgs.writeShellApplication {
      name = "contract-mirror";
      runtimeInputs = [pkgs.gnused pkgs.diffutils];
      text = ''
        extract() {
          sed -n '/ANCHOR: consumer-contract/,/ANCHOR_END: consumer-contract/p' "$1" |
            sed '1d;$d' | sed '/^[[:space:]]*$/d'
        }

        if ! diff -u \
          --label CONTRIBUTING.md <(extract CONTRIBUTING.md) \
          --label CLAUDE.md <(extract CLAUDE.md); then
          echo "contract-mirror: the consumer-contract blocks have drifted." >&2
          echo "CONTRIBUTING.md is canonical. Copy its block into CLAUDE.md." >&2
          exit 1
        fi
      '';
    };

    # The four numbered clauses of the consumer contract, as a static check.
    # contract-mirror keeps the prose in CONTRIBUTING.md and CLAUDE.md
    # identical; this keeps the tree honest about it. Run from a repository root.
    #
    # Clauses 1 and 2 fail at evaluation only in the cases a fixture happens to
    # cover. A module that accepts a `username` argument from a fleet that
    # provides one evaluates cleanly and still breaks any other consumer, and an
    # unguarded per-user write only shows up on a host shape nobody tests. A
    # grep catches both the moment the module is written.
    contractGuards = pkgs.writeShellApplication {
      name = "contract-guards";
      runtimeInputs = [pkgs.gnugrep pkgs.findutils pkgs.coreutils];
      text = ''
        fail=0
        report() {
          fail=1
          echo "contract-guards: $1" >&2
          shift
          printf '  %s\n' "$@" >&2
        }

        # Clause 2, home-manager half. Stated as a prohibition rather than a
        # correlation: modules route per-user config through
        # othrys.internal.homeConfig and othrys.system.users applies the
        # homeManaged guard once. A correlation ("a module writing
        # home-manager.users must also mention homeManaged") can be satisfied by
        # a guard on the wrong node; this cannot be satisfied by accident.
        #
        # A read is `config.home-manager.users...`, which is how
        # apps/gui/vscode reaches nixvim's build product. Only writes lack the
        # `config.` prefix, so that prefix is the discriminator.
        hm_writes=$(grep -rn --include='*.nix' -E '(^|[^.a-zA-Z])home-manager\.users' modules \
          | grep -v '^modules/system/users\.nix:' \
          | grep -v 'config\.home-manager\.users' \
          | grep -vE '^[^:]+:[0-9]+: *#' || true)
        [ -z "$hm_writes" ] || report \
          "only modules/system/users.nix may write home-manager.users; route per-user config through othrys.internal.homeConfig:" \
          "$hm_writes"

        # Clause 2, account half. Every module creating the primary account
        # guards on othrys.system.users.enable, at the attrset level.
        account_unguarded=()
        while IFS= read -r f; do
          [ "$f" = "modules/system/users.nix" ] && continue
          grep -q 'usersEnabled\|othrys\.system\.users\.enable' "$f" || account_unguarded+=("$f")
        done < <(grep -rln --include='*.nix' -E '^ *users\.users' modules | sort)
        [ ''${#account_unguarded[@]} -eq 0 ] ||
          report "modules writing users.users without an othrys.system.users.enable guard:" "''${account_unguarded[@]}"

        # Clause 1. No module takes a `username` argument. Identity is read from
        # othrys.system.user.name, which has no default.
        username_args=$(grep -rn --include='*.nix' -E '^ *username,' modules flake || true)
        [ -z "$username_args" ] ||
          report "modules must read config.othrys.system.user.name, not take a username argument:" "$username_args"

        # Clause 4. specialArgs carry `inputs` alone wherever a host or a NixOS
        # test is built. Bare lib.evalModules fixtures with stub option trees are
        # not a consumer path and pass what they need, so the rule is scoped to
        # files that actually build one.
        bad_special=()
        while IFS= read -r f; do
          grep -q 'nixosSystem\|nixosTest\|runTest' "$f" || continue
          while IFS= read -r hit; do
            case "$hit" in
              *'{inherit inputs;}'*) ;;
              *) bad_special+=("$f: $hit") ;;
            esac
          done < <(grep -hoE 'specialArgs = \{[^}]*\}' "$f")
        done < <(grep -rl --include='*.nix' 'specialArgs' . | sed 's|^\./||' | sort)
        [ ''${#bad_special[@]} -eq 0 ] ||
          report "specialArgs must carry inputs alone where a host or NixOS test is built:" "''${bad_special[@]}"

        [ "$fail" -eq 0 ] || exit 1
        echo "contract-guards: ok"
      '';
    };

    # Comment and docs hygiene: the Comments and Anchors conventions from
    # CONTRIBUTING.md, plus docs page and link integrity. Run from a repository root.
    commentHygiene = pkgs.writeShellApplication {
      name = "comment-hygiene";
      runtimeInputs = [pkgs.gnugrep pkgs.findutils pkgs.coreutils pkgs.gnused];
      text = ''
        fail=0
        report() {
          fail=1
          echo "comment-hygiene: $1" >&2
          shift
          printf '  %s\n' "$@" >&2
        }

        # 1. Every .nix under modules/ and flake/ opens with its own
        #    repository-relative path, then a purpose line. These files are read
        #    as {{#include}} fragments stripped of their filename.
        missing_header=()
        while IFS= read -r f; do
          [ "$(sed -n '1p' "$f")" = "# $f" ] || { missing_header+=("$f"); continue; }
          case "$(sed -n '2p' "$f")" in
            '#'*) ;;
            *) missing_header+=("$f (no purpose line)") ;;
          esac
        done < <(find modules flake -name '*.nix' | sort)
        [ ''${#missing_header[@]} -eq 0 ] ||
          report "files missing the '# <path>' + purpose header:" "''${missing_header[@]}"

        # 2. No banner rules. A run of three or more '=' inside a comment.
        banners=$(grep -rn -E '^[[:space:]]*(#|--)[[:space:]]*={3,}' \
          --include='*.nix' --include='*.sh' modules flake scripts flake.nix justfile || true)
        [ -z "$banners" ] || report "banner comments (see Comments and Anchors in CONTRIBUTING.md):" "$banners"

        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT

        # 3. Every ANCHOR has a matching ANCHOR_END, in any comment syntax.
        grep -rhoE 'ANCHOR: *[A-Za-z0-9_-]+' . 2>/dev/null |
          sed 's/ANCHOR: *//' | sort > "$work/open"
        grep -rhoE 'ANCHOR_END: *[A-Za-z0-9_-]+' . 2>/dev/null |
          sed 's/ANCHOR_END: *//' | sort > "$work/close"
        unbalanced=$(comm -3 "$work/open" "$work/close" || true)
        [ -z "$unbalanced" ] || report "unbalanced ANCHOR / ANCHOR_END:" "$unbalanced"

        # 4. Every docs page is a SUMMARY.md chapter (mdBook renders no HTML
        #    for unlisted pages, so links at them 404), and every relative .md
        #    link resolves to a file.
        orphan_pages=()
        dead_links=()
        while IFS= read -r p; do
          rel=''${p#docs/src/}
          [ "$rel" = "reference/options.md" ] && continue
          grep -qF "($rel)" docs/src/SUMMARY.md || grep -qF "(./$rel)" docs/src/SUMMARY.md ||
            orphan_pages+=("$rel")
          while IFS= read -r t; do
            [ -f "$(dirname "$p")/$t" ] || [ "''${t##*/}" = "options.md" ] ||
              dead_links+=("$rel -> $t")
          done < <(awk '/^```/{b=!b} !b' "$p" |
            grep -oE '\]\([^)#]+\.md(#[^)]*)?\)' |
            sed -E 's/^\]\(//; s/\)$//; s/#.*//' | sort -u)
        done < <(find docs/src -name '*.md' ! -name SUMMARY.md | sort)
        [ ''${#orphan_pages[@]} -eq 0 ] ||
          report "docs pages missing from SUMMARY.md:" "''${orphan_pages[@]}"
        [ ''${#dead_links[@]} -eq 0 ] ||
          report "dead relative links in docs:" "''${dead_links[@]}"

        # 5. Every defined anchor is embedded by at least one docs page. Every
        #    option is already published in the generated reference, so an
        #    anchor no page includes is duplication with nothing reading it.
        grep -rhoE '\{\{#include [^}]*:[A-Za-z0-9_-]+\}\}' docs/src 2>/dev/null |
          sed -E 's/.*:([A-Za-z0-9_-]+)\}\}/\1/' | sort -u > "$work/used"
        sort -u "$work/open" > "$work/defined"
        orphans=$(comm -23 "$work/defined" "$work/used" || true)
        [ -z "$orphans" ] || report "anchors defined but never included by docs/src:" "$orphans"

        [ "$fail" -eq 0 ] || exit 1
        echo "comment-hygiene: ok"
      '';
    };

    # Force a host's toplevel derivation so any option/module error fails the
    # check. Only the tiny wrapper is realised, not the system.
    mkHostEval = name: hostModules:
      pkgs.runCommand name {
        drv =
          (inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = {inherit inputs;};
            modules = upstreamModules ++ hostModules;
          })
          .config
          .system
          .build
          .toplevel
          .drvPath;
      } "echo \"$drv\" > \"$out\"";
  in {
    # ANCHOR: checks
    # Checks are split into two tiers. The GitHub workflow runs CORE on every PR
    # and EXTENDED only on main + manual dispatch (see .github/workflows).
    # `nix flake check` locally still runs all of them.
    checks = {
      # CORE, fast, every PR

      # The least it takes for othrys to produce a bootable Linux host. Small
      # closure, so it's the cheap gate that catches most option/module errors.
      eval-host-min = mkHostEval "othrys-eval-host-min" [functioningHost];

      # Regression guard for headless/root-only hosts, with nix settings enabled but
      # NO primary user account (othrys.system.users stays off). othrys.system.nix
      # must not materialize a home-manager user here, since doing so trips NixOS's
      # user assertions. See modules/system/nix.nix.
      eval-host-headless = mkHostEval "othrys-eval-host-headless" [
        bootBase
        {
          othrys.system.nix = {
            enable = true;
            stateVersion = "26.05";
          };
        }
      ];

      # Server contract, named variant. A headless host with a declared user
      # name but NO managed account (users.enable off) must be able to run the
      # full server module surface. Catches per-user writes that escape the
      # users.enable guard (materialized home-manager users, phantom accounts).
      eval-host-server = mkHostEval "othrys-eval-host-server" [
        bootBase
        {
          othrys.system.nix = {
            enable = true;
            stateVersion = "26.05";
          };
        }
        serverModules
      ];

      # Server contract, anonymous variant. The same surface with
      # othrys.system.user.name entirely unset. Guards the "decoupled
      # foundation" invariant, so no server module may force a primary user
      # identity to exist.
      eval-host-anonymous = mkHostEval "othrys-eval-host-anonymous" [
        bootCore
        {
          othrys.system.nix = {
            enable = true;
            stateVersion = "26.05";
          };
        }
        serverModules
      ];

      # Server contract, account-without-home-manager variant. The primary
      # account exists (e.g. an admin login, or a user a webapp runs under)
      # but home-manager does not manage its environment
      # (users.homeManager.enable off). Guards the account/environment split,
      # no module may write home-manager state keyed on account creation alone.
      eval-host-server-account = mkHostEval "othrys-eval-host-server-account" [
        bootBase
        {
          othrys.system.nix = {
            enable = true;
            stateVersion = "26.05";
          };
          othrys.system.users = {
            enable = true;
            homeManager.enable = false;
            # Bootstrap hash for "changeme", generated with mkpasswd -m yescrypt.
            initialHashedPassword = "$y$j9T$aiZuvauf85ZjB04z3seyG0$OKYG9I1g.vAp5IA48MlGzaVoB15gqWIL.k7lSni8fe8";
          };
        }
        serverModules
      ];

      # App/desktop contract, account-without-home-manager variant. The gap the
      # guard sweep closed: every headless fixture above enables the SERVER
      # module surface and never an app or desktop module, so thirty-two
      # unguarded per-user writes sat undetected. A managed account with
      # home-manager off must be able to enable app modules without any of them
      # materializing a home-manager user.
      #
      # A cheap representative slice runs here in CORE, one CLI module, one GUI
      # module, one desktop module, and vscode for its cross-read of nixvim's
      # build product. The full set runs in EXTENDED below, since a subset only
      # proves that a subset is guarded.
      eval-host-app-no-hm = mkHostEval "othrys-eval-host-app-no-hm" [
        accountNoHomeManager
        {
          othrys.apps.gh.enable = true;
          othrys.apps.ghostty.enable = true;
          othrys.apps.vscode.enable = true;
          othrys.desktop.graphical = true;
          othrys.desktop.idle.enable = true;
        }
      ];

      # EXTENDED, heavy, main and manual dispatch

      # The same contract over every app and desktop module that writes per-user
      # configuration. Heavy enough for EXTENDED (browser and Electron closures
      # evaluate here), and the only fixture that proves the claim for all of
      # them rather than for four.
      eval-host-app-no-hm-full = mkHostEval "othrys-eval-host-app-no-hm-full" [
        accountNoHomeManager
        appDesktopModules
      ];

      # The exclusive shell layer, which asserts against ashell, idle and
      # nightLight and so cannot ride in the fixture above. Small on its own,
      # and without it noctalia would be the one per-user module no fixture
      # covers on an unmanaged host.
      eval-host-app-no-hm-noctalia = mkHostEval "othrys-eval-host-app-no-hm-noctalia" [
        accountNoHomeManager
        {
          othrys.system.stylix.enable = true;
          othrys.desktop.graphical = true;
          othrys.desktop.compositors.niri.enable = true;
          othrys.desktop.noctalia.enable = true;
        }
      ];

      # Whole-tree evaluation over the minimal host plus theming and the mangohud
      # settings merge (mangohud reads Stylix colors, so both must be on. This
      # pairing caught the mangohud x Stylix conflict). Heavier GUI apps (floorp,
      # vesktop) are left out so this doesn't pull a browser/Electron closure;
      # their merges are trivial `//` unions covered by plain eval + parse.
      eval-default = mkHostEval "othrys-eval-default" [
        functioningHost
        {
          othrys.system.shell.zsh.enable = true;
          othrys.system.stylix.enable = true;
          othrys.apps.gaming.mangohud.enable = true;
        }
      ];

      # Desktop-session surface with MODULE DEFAULTS, covering compositor, bar, login,
      # session manager, prompt, none of which eval-default covers. Notably
      # hyprland is evaluated with its default (unnamed) monitor config, which
      # once crashed workspace auto-generation, so this check pins enable-with-
      # defaults working for the whole desktop stack.
      eval-host-desktop = mkHostEval "othrys-eval-host-desktop" [
        functioningHost
        {
          othrys.system.stylix.enable = true;
          othrys.system.shell.zsh.enable = true;
          othrys.system.shell.starship.enable = true;
          othrys.desktop.compositors.hyprland.enable = true;
          othrys.desktop.ashell.enable = true;
          othrys.desktop.uwsm.enable = true;
          othrys.desktop.login = {
            enable = true;
            defaultDesktop = "hyprland";
          };
          othrys.services.automount.enable = true;
          othrys.desktop.graphical = true;
          othrys.desktop.idle.enable = true;
          othrys.desktop.nightLight.enable = true;
          othrys.hardware.scanner.enable = true;
          # Pins two failure classes, an unfree package inside home-manager
          # (needs useGlobalPkgs to see nixpkgs.config.allowUnfree) and a
          # cross-module HM dereference (vscode reads nixvim's package).
          # allowUnfree is opt-in, so a host wanting claude-code says so.
          othrys.system.nix.allowUnfree = true;
          othrys.apps.ai.claude-code.enable = true;
          othrys.apps.nixvim.enable = true;
          othrys.apps.vscode.enable = true;
          # Exercise the shared language toolchain path, from signal to shared
          # binaries on PATH -> both editors pointing at them.
          othrys.apps.languages.nix.enable = true;
          othrys.apps.languages.python.enable = true;
          # Both compositors enabled at once (greeter picks the session):
          # coexistence must eval, with one graphical flag and two config surfaces.
          othrys.desktop.compositors.niri.enable = true;
        }
      ];

      # Niri-only desktop with the noctalia shell (the ashell alternative,
      # both shells stay covered, since ashell rides eval-host-desktop). Login
      # starts niri-session directly and defaultDesktop stays UNSET,
      # pinning that sessionCommand doesn't force the uwsm-path option.
      eval-host-desktop-niri = mkHostEval "othrys-eval-host-desktop-niri" [
        functioningHost
        {
          othrys.system.stylix.enable = true;
          othrys.desktop.compositors.niri.enable = true;
          othrys.desktop.noctalia.enable = true;
          othrys.desktop.login = {
            enable = true;
            sessionCommand = "niri-session";
          };
          # idle/nightLight must stay OFF here, since noctalia owns both and their
          # conflict assertions are exercised by the enable matrix instead.
        }
      ];

      # EXTENDED. Enable-with-defaults matrix (see ./enable-matrix.nix).
      enable-matrix = import ./enable-matrix.nix {
        inherit pkgs inputs system upstreamModules bootCore bootBase functioningHost;
      };

      # EXTENDED. Runtime VM tests, one file each.
      integration-test = import ./integration.nix {inherit pkgs inputs;};
      restic-test = import ./restic.nix {inherit pkgs inputs;};
      crowdsec-test = import ./crowdsec.nix {inherit pkgs inputs;};
      headscale-test = import ./headscale.nix {inherit pkgs inputs;};

      # CORE. Pre-commit hooks check (treefmt formats, statix and deadnix lint,
      # comment-hygiene enforces the CONTRIBUTING.md comment conventions).
      pre-commit-check = inputs.git-hooks.lib.${system}.run {
        src = inputs.self;
        hooks = {
          treefmt = {
            enable = true;
            package = config.treefmt.build.wrapper;
          };
          statix.enable = true;
          deadnix.enable = true;
          commitizen.enable = true;
          comment-hygiene = {
            enable = true;
            name = "comment-hygiene";
            entry = "${commentHygiene}/bin/comment-hygiene";
            pass_filenames = false;
          };
          contract-mirror = {
            enable = true;
            name = "contract-mirror";
            entry = "${contractMirror}/bin/contract-mirror";
            pass_filenames = false;
          };

          contract-guards = {
            enable = true;
            name = "contract-guards";
            entry = "${contractGuards}/bin/contract-guards";
            pass_filenames = false;
          };
        };
      };

      # CORE. The comment conventions in CONTRIBUTING.md are only a convention
      # until something fails on them. The 56 banner rules this check now
      # rejects accumulated while a written rule against them already existed.
      comment-hygiene =
        pkgs.runCommand "othrys-comment-hygiene" {
          nativeBuildInputs = [commentHygiene];
        } ''
          cd ${inputs.self}
          comment-hygiene
          touch $out
        '';

      # CORE. The consumer contract, enforced rather than described. The
      # home-manager clause held for twenty of fifty-two modules while the prose
      # said all of them, and nothing failed, because the fixtures never enabled
      # an app module on a host without a managed user.
      contract-guards =
        pkgs.runCommand "othrys-contract-guards" {
          nativeBuildInputs = [contractGuards];
        } ''
          cd ${inputs.self}
          contract-guards
          touch $out
        '';

      # CORE. The mdbook build fails on broken `{{#include …:anchor}}` references,
      # so docs/module drift (missing anchors, renamed files) is caught by CI
      # instead of only surfacing on a manual `just docs build`. The generated
      # options reference is injected first (see flake/docs-options.nix).
      docs = pkgs.stdenv.mkDerivation {
        name = "othrys-docs";
        src = inputs.self;
        nativeBuildInputs = [pkgs.mdbook];
        buildPhase = ''
          install -m644 ${config.packages.options-doc} docs/src/reference/options.md
          mdbook build docs/
        '';
        installPhase = "cp -r docs/book $out";
      };

      # CORE. The impermanence root-wipe invariant (see ./impermanence.nix).
      impermanence-test = import ./impermanence.nix {inherit pkgs inputs;};
    };
    # ANCHOR_END: checks
  };
}
