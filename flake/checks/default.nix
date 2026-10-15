# flake/checks/default.nix
# CI/CD validation checks: shared fixtures, the eval checks, and wiring for the heavy checks in this directory
{inputs, ...}: {
  perSystem = {
    system,
    config,
    pkgs,
    ...
  }: let
    # The othrys tree and nothing beside it, which is what every fixture
    # starts from. `default` writes into no option namespace of an upstream
    # flake, so a fixture built from this list alone shows that it evaluates
    # on a host that imports none of Home Manager, Stylix, disko, sops-nix and
    # impermanence. A fixture that wants one of the five lists the matching
    # module below among its own.
    defaultModules = [
      inputs.self.nixosModules.default
    ];

    # The Home Manager module and the othrys adapter that hands it the
    # per-user registry, which a consumer imports together or not at all.
    # functioningHost carries it, and so does any other fixture with a
    # managed user or one that reads home-manager.users. The headless and
    # server fixtures leave it out, and the account that Home Manager does
    # not manage does too.
    homeModules = {
      imports = [
        inputs.home-manager.nixosModules.home-manager
        inputs.self.nixosModules.home
      ];
    };

    # The impermanence module and the othrys adapter that hands it the
    # persistence registry, which a consumer imports together or not at all.
    # A fixture that sets othrys.system.impermanence.enable lists this module
    # among its own, and so does one that reads environment.persistence with
    # impermanence off.
    impermanenceModules = {
      imports = [
        inputs.impermanence.nixosModules.impermanence
        inputs.self.nixosModules.impermanence
      ];
    };

    # The Stylix module and the othrys adapter, which a consumer imports
    # together or not at all. A fixture that wants Stylix lists this module
    # among its own and sets othrys.system.stylix.enable.
    stylixModules = {
      imports = [
        inputs.stylix.nixosModules.stylix
        inputs.self.nixosModules.stylix
      ];
    };

    # The disko module and the othrys disk layout, which a consumer imports
    # together or not at all. A fixture that sets othrys.system.disko lists
    # this module among its own.
    diskoModules = {
      imports = [
        inputs.disko.nixosModules.disko
        inputs.self.nixosModules.disko
      ];
    };

    # The sops-nix module and the othrys secrets plumbing, on the same terms.
    # A fixture that sets othrys.system.secrets lists this module among its
    # own.
    secretsModules = {
      imports = [
        inputs.sops-nix.nixosModules.sops
        inputs.self.nixosModules.secrets
      ];
    };

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
    #
    # It turns the secrets plumbing on, so it carries the sops-nix module and
    # the secrets export itself.
    serverModules = {
      imports = [secretsModules];
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
      # Off-loopback deliberately. Upstream ntfy-sh defines settings.listen-http
      # at mkDefault, and a priority tie with the string othrys writes would
      # merge silently and prove nothing. Any address upstream does not write
      # keeps this eval failing if the generated leaves ever tie with upstream.
      othrys.services.ntfy = {
        enable = true;
        listenAddress = "0.0.0.0";
      };
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
    # It imports neither the Home Manager module nor the export, so the host
    # has no home-manager option namespace at all.
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

    # Every app and desktop module that configures the primary user. hyprland
    # stands for the compositor pair, with niri covered by
    # eval-host-desktop-niri.
    #
    # Two modules are set past their defaults, since each holds a code path a
    # bare enable never reaches. IDEA repackages the IDE only when a plugin is
    # selected, and Steam writes steam_dev.cfg only when a console variable is
    # set. Both are per-user writes, so they are rendered on the managed host
    # of eval-persistence, which forces its toplevel.
    appDesktopModules = {
      # The sops-nix module and the secrets export, for the enable below.
      imports = [secretsModules];

      # Prerequisites the modules below assert on, rather than things under
      # test. Several apps refuse to evaluate without a Steam install or a
      # JDK. The secrets module is on beside them, so the impermanence hosts
      # of eval-persistence evaluate the whole set next to it.
      othrys.system.secrets.enable = true;
      othrys.system.nix.allowUnfree = true;
      othrys.desktop.graphical = true;
      othrys.apps.gaming.steam = {
        enable = true;
        shaderPrecache.backgroundThreads = 4;
        devConfig = {
          "@nClientDownloadEnableHTTP2PlatformLinux" = 0;
          "@fDownloadRateImprovementToAddAnotherConnection" = "1.0";
        };
      };
      othrys.apps.languages.java.enable = true;

      othrys.apps = {
        ai.claude-code.enable = true;
        ai.mcp.context7.enable = true;
        ai.mcp.nixos.enable = true;
        ai.ollama.enable = true;
        comma.enable = true;
        chromium.enable = true;
        development.enable = true;
        gh.enable = true;
        nixvim.enable = true;
        yazi.enable = true;
        discord.enable = true;
        floorp.enable = true;
        gaming.gamemode.enable = true;
        gaming.mangohud.enable = true;
        gaming.osu.enable = true;
        gaming.prismlauncher.enable = true;
        gaming.r2modman.enable = true;
        ghostty.enable = true;
        idea = {
          enable = true;
          plugins.ideavim = true;
        };
        kitty.enable = true;
        localsend.enable = true;
        mpv.enable = true;
        obs.enable = true;
        picard.enable = true;
        plexamp.enable = true;
        rustdesk.enable = true;
        signal.enable = true;
        vesktop.enable = true;
        vscode.enable = true;
      };
      othrys.desktop = {
        ashell.enable = true;
        compositors.hyprland.enable = true;
        idle.enable = true;
        vicinae.enable = true;
        # The night light asks for a location, and these are placeholders.
        nightLight = {
          enable = true;
          latitude = 0.0;
          longitude = 0.0;
        };
      };
    };

    # bootBase plus the core system modules a functioning workstation host needs
    # (a managed user account, nix settings, git), and the Home Manager module
    # with its export, since Home Manager manages that account.
    functioningHost = {
      imports = [bootBase homeModules];
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

    # CONTRIBUTING.md holds the canonical consumer contract, and AGENTS.md keeps
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
          --label AGENTS.md <(extract AGENTS.md); then
          echo "contract-mirror: the consumer-contract blocks have drifted." >&2
          echo "CONTRIBUTING.md is canonical. Copy its block into AGENTS.md." >&2
          exit 1
        fi
      '';
    };

    # The four numbered clauses of the consumer contract, as a static check.
    # contract-mirror keeps the prose in CONTRIBUTING.md and AGENTS.md
    # identical; this keeps the tree honest about it. Run from a repository root.
    #
    # Clauses 1 and 2 fail at evaluation only in the cases a fixture happens to
    # cover. A module that accepts a `username` argument from a fleet that
    # provides one evaluates cleanly and still breaks any other consumer, and an
    # unguarded per-user write only shows up on a host shape nobody tests. A
    # grep catches both the moment the module is written.
    #
    # A grep reads spelling, and an argument set written on one line or a
    # specialArgs set written across several passes it. eval-contract
    # (./contract-eval.nix) reads clauses 1, 2 and 4 back from evaluation, and
    # the two run side by side, since the greps also cover flake/ and the
    # account half of clause 2.
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
        # othrys.internal.homeConfig and nixosModules.home applies the
        # homeManaged guard once. A correlation ("a module writing
        # home-manager.users must also mention homeManaged") can be satisfied by
        # a guard on the wrong node; this cannot be satisfied by accident.
        #
        # A read counts as well. home-manager.users is declared by the Home
        # Manager module, which `default` does not import, so a module that
        # read config.home-manager.users would fail on every host without it.
        hm_writes=$(grep -rn --include='*.nix' -E '(^|[^.a-zA-Z])home-manager\.users' modules \
          | grep -v '^modules/system/home\.nix:' \
          | grep -vE '^[^:]+:[0-9]+: *#' || true)
        [ -z "$hm_writes" ] || report \
          "only modules/system/home.nix may name home-manager.users; route per-user config through othrys.internal.homeConfig:" \
          "$hm_writes"

        # Clause 3. Every other home-manager option is held to the same file,
        # with one exception. The Stylix adapter is outside `default` and
        # writes home-manager.sharedModules behind a test for the namespace.
        hm_options=$(grep -rn --include='*.nix' -E '(^|[^.a-zA-Z-])home-manager\.[a-zA-Z]' modules \
          | grep -v '^modules/system/home\.nix:' \
          | grep -v '^modules/theme/stylix\.nix:' \
          | grep -vE '^[^:]+:[0-9]+: *#' || true)
        [ -z "$hm_options" ] || report \
          "only modules/system/home.nix may write into the home-manager option namespace:" \
          "$hm_options"

        # Clause 2, account half. Every module creating the primary account
        # guards on othrys.system.users.enable, at the attrset level.
        account_unguarded=()
        while IFS= read -r f; do
          [ "$f" = "modules/system/users.nix" ] && continue
          grep -q 'usersEnabled\|othrys\.system\.users\.enable' "$f" || account_unguarded+=("$f")
        done < <(grep -rln --include='*.nix' -E '^ *users\.users' modules | sort)
        [ ''${#account_unguarded[@]} -eq 0 ] ||
          report "modules writing users.users without an othrys.system.users.enable guard:" "''${account_unguarded[@]}"

        # Clause 2, persistence half. Stated as a prohibition as well: modules
        # name what they persist in othrys.internal.persist, and
        # nixosModules.impermanence applies the impermanence and account
        # guards once. environment.persistence is declared by the impermanence
        # module, which `default` does not import, so a write from any other
        # file fails on every host without that module.
        persist_writes=$(grep -rn --include='*.nix' 'environment\.persistence' modules \
          | grep -v '^modules/system/impermanence\.nix:' \
          | grep -vE '^[^:]+:[0-9]+: *#' || true)
        [ -z "$persist_writes" ] || report \
          "only modules/system/impermanence.nix may name environment.persistence; declare persistent paths in othrys.internal.persist:" \
          "$persist_writes"

        # Clause 1. No module takes a `username` argument. Identity is read from
        # othrys.system.user.name, which has no default.
        username_args=$(grep -rn --include='*.nix' -E '^ *username,' modules flake || true)
        [ -z "$username_args" ] ||
          report "modules must read config.othrys.system.user.name, not take a username argument:" "$username_args"

        # Clause 4. specialArgs carry `inputs` alone, or nothing, wherever a
        # host or a NixOS test is built. Bare lib.evalModules fixtures with stub
        # option trees are not a consumer path and pass what they need, so the
        # rule is scoped to files that actually build one.
        bad_special=()
        while IFS= read -r f; do
          grep -q 'nixosSystem\|nixosTest\|runTest' "$f" || continue
          while IFS= read -r hit; do
            case "$hit" in
              *'{inherit inputs;}'*|*'{}'*) ;;
              *) bad_special+=("$f: $hit") ;;
            esac
          done < <(grep -hoE 'specialArgs = \{[^}]*\}' "$f")
        done < <(grep -rl --include='*.nix' 'specialArgs' . | sed 's|^\./||' | sort)
        [ ''${#bad_special[@]} -eq 0 ] ||
          report "specialArgs must carry inputs alone, or nothing, where a host or NixOS test is built:" "''${bad_special[@]}"

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

    # The resolver the docs checks run (./docs-includes.py). mdbook logs an
    # include it cannot read, renders the page without it and exits 0, so the
    # resolver is what fails on a missing file, anchor, page or heading.
    docsIncludes = pkgs.writeShellApplication {
      name = "docs-includes";
      runtimeInputs = [pkgs.python3];
      text = ''
        exec python3 ${./docs-includes.py} "$@"
      '';
    };

    # One book per broken case, each expected to fail with its own reason, and
    # one sound book expected to pass. The directive and the anchor marker are
    # assembled from parts, so the anchor scan in comment-hygiene does not read
    # the fixtures as anchors of this file.
    docsIncludesFixtures = pkgs.writeShellApplication {
      name = "docs-includes-fixtures";
      runtimeInputs = [docsIncludes pkgs.coreutils pkgs.gnugrep];
      text = ''
        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT
        fail=0
        mark=ANCHOR
        inc="{{#include ../../modules/a.nix"

        # fixture <name> <expected reason, empty when the book is sound> <page line>...
        fixture() {
          local name=$1 want=$2
          shift 2
          rm -rf "$work/book"
          mkdir -p "$work/book/docs/src" "$work/book/modules"
          printf '%s\n' "# Page" "$@" > "$work/book/docs/src/page.md"
          printf '%s\n' "# $mark: region" "kept = true;" "# ''${mark}_END: region" "# $mark: open" \
            > "$work/book/modules/a.nix"
          if docs-includes "$work/book/docs/src" > "$work/out" 2>&1; then
            [ -z "$want" ] && return 0
            echo "docs-includes-fixtures: '$name' passed and must fail" >&2
          else
            [ -n "$want" ] && grep -qF -- "$want" "$work/out" && return 0
            echo "docs-includes-fixtures: '$name' did not report '$want':" >&2
            cat "$work/out" >&2
          fi
          fail=1
        }

        fixture "sound book" "" "$inc:region}}" "$inc:1:2}}" "$inc}}" "[top](#page)" "[self](./page.md#page)"
        fixture "missing file" "no file at" "{{#include ../../modules/gone.nix:region}}"
        fixture "missing anchor" "no ANCHOR marker named 'absent'" "$inc:absent}}"
        fixture "unclosed anchor" "no ANCHOR_END marker named 'open'" "$inc:open}}"
        fixture "range past the end" "past the end" "$inc:99}}"
        fixture "missing rustdoc include" "no file at" "{{#rustdoc_include ../../modules/gone.rs:region}}"
        fixture "missing page" "no file at" "[gone](./gone.md)"
        fixture "missing heading" "no heading with id 'nowhere'" "[gone](#nowhere)"
        fixture "missing heading on another page" "no heading with id 'nowhere'" "[gone](./page.md#nowhere)"

        [ "$fail" -eq 0 ] || exit 1
        echo "docs-includes-fixtures: ok"
      '';
    };

    # A host built the way a consumer builds one, as the whole evaluation.
    # `options` and `_module` sit beside `config` there, which is what lets a
    # check read where a definition came from and which specialArgs it was
    # handed.
    hostEval = hostModules:
      inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs;};
        modules = defaultModules ++ hostModules;
      };

    # The evaluated config of such a host.
    hostConfig = hostModules: (hostEval hostModules).config;

    # The default template, instantiated with its othrys input pointed at this
    # flake and only the inputs a consumer would have. Home Manager is the one
    # upstream flake among them. disko, sops-nix and impermanence are not,
    # since the template declares none.
    templateHost =
      ((import ../../templates/default/flake.nix).outputs {
        othrys = inputs.self;
        inherit (inputs) nixpkgs home-manager;
      }).nixosConfigurations.myhost;

    # Files under modules/ that are not modules. Each is a plain function or
    # plain data that modules import directly, and says so in its header.
    moduleHelpers = [
      "modules/desktop/compositors/hyprland-lua.nix"
      "modules/desktop/session.nix"
      "modules/theme/schemes/oxocarbon.nix"
    ];

    # Force a host's toplevel derivation so any option/module error fails the
    # check. Only the tiny wrapper is realised, not the system. The string
    # context is dropped because it would make the system's .drv file an input
    # of the wrapper, and `nix flake check --no-build` does not write that file
    # to the store, so it fails with "path ... .drv is not valid" whenever the
    # system derivation is new. Evaluation is forced either way.
    mkHostEval = name: hostModules:
      pkgs.runCommand name {
        drv = builtins.unsafeDiscardStringContext (hostConfig hostModules).system.build.toplevel.drvPath;
      } "echo \"$drv\" > \"$out\"";

    # Compare values read back from evaluated hosts. `expectations` maps a
    # label to a boolean, and the check fails naming every label that is false.
    # mkHostEval only proves a host evaluates, which says nothing about what a
    # module actually wrote.
    mkExpectations = name: expectations:
      pkgs.runCommand name {
        failed = builtins.concatStringsSep "\n" (builtins.attrNames (inputs.nixpkgs.lib.filterAttrs (_: ok: !ok) expectations));
        total = toString (builtins.length (builtins.attrNames expectations));
      } ''
        if [ -n "$failed" ]; then
          echo "${name}: expectations not met:" >&2
          printf '%s\n' "$failed" | sed 's/^/  - /' >&2
          exit 1
        fi
        echo "$total expectations met" > "$out"
      '';

    # True when the host carries a failing assertion whose message mentions
    # `needle`. Reads config.assertions directly, since forcing the toplevel of
    # a host that is meant to be rejected aborts the evaluation instead.
    rejectedWith = needle: cfg:
      builtins.any (a: !a.assertion && inputs.nixpkgs.lib.hasInfix needle a.message) cfg.assertions;

    # A headless host with the hardening profile and both costly switches on,
    # next to Tailscale, whose firewall setting the profile has to respect, and
    # one plain sysctl assignment the profile has to lose to.
    hardenedHost = hostConfig [
      bootBase
      {
        othrys.system.nix = {
          enable = true;
          stateVersion = "26.05";
        };
        othrys.services.firewall.enable = true;
        othrys.services.tailscale.enable = true;
        othrys.system.hardening = {
          enable = true;
          lockKernelModules = true;
          protectKernelImage = true;
        };
        boot.kernel.sysctl."kernel.yama.ptrace_scope" = 0;
      }
    ];

    # The profile next to the router module, which assigns strict rp_filter
    # to its WAN interface and loose to the rest.
    hardenedRouter = hostConfig [
      bootBase
      {
        othrys.system.nix = {
          enable = true;
          stateVersion = "26.05";
        };
        othrys.services.router = {
          enable = true;
          wan.interface = "wan0";
          lan.interfaces = ["lan0"];
        };
        othrys.system.hardening.enable = true;
      }
    ];

    # The profile with protectKernelImage on a host configured to hibernate.
    hibernatingHost = hibernation:
      hostConfig [
        bootBase
        hibernation
        {
          othrys.system.hardening = {
            enable = true;
            protectKernelImage = true;
          };
        }
      ];

    # The hooks come in two sets, named here once. Both the check below and the
    # dev shells (../dev-shells.nix) are built from them, so a local commit in
    # this repository meets exactly what CI runs.
    #
    # hygiene-scan refuses text that would put private infrastructure into this
    # public tree. It covers what a pattern can prove and nothing else. A
    # hostname or a person's name needs a reader, and gitleaks already covers
    # key material. With no argument it scans what git has staged, including
    # renames. The pre-commit hook passes file names so CI scans its checkout
    # even after git-hooks commits it. With file names it scans those files. With
    # `-` it scans standard input, and an optional second argument names the
    # path the text is bound for, so the exemptions below still apply.
    hygieneScan = pkgs.writeShellApplication {
      name = "hygiene-scan";
      runtimeInputs = [pkgs.gnugrep pkgs.gnused pkgs.coreutils pkgs.git];
      text = ''
        fail=0
        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT

        report() {
          fail=1
          echo "hygiene-scan: $1: $2" >&2
          sed 's/^/  /' >&2
        }

        # scan <path the text belongs to> <file holding the text>
        scan() {
          local path=$1 file=$2 hits

          # AGENTS.md names the scheme in the rule that forbids it.
          if [ "$path" != AGENTS.md ]; then
            hits=$(grep -InE 'git\+ssh://' "$file" || true)
            [ -z "$hits" ] || report "$path" "an SSH flake URL, which names a private input" <<< "$hits"
          fi

          hits=$(grep -InE 'ENC\[AES256_GCM,data:' "$file" || true)
          [ -z "$hits" ] || report "$path" "a sops-encrypted value" <<< "$hits"

          hits=$(grep -InE 'AGE-SECRET-KEY-1[0-9A-Z]{20,}' "$file" || true)
          [ -z "$hits" ] || report "$path" "an age secret key" <<< "$hits"

          # An address inside the carrier-grade NAT range is a tailnet node.
          # The range itself, written as a CIDR, is not.
          hits=$(grep -InoE '(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+(/[0-9]+)?' "$file" |
            grep -vE '100\.64\.0\.0/10$' || true)
          [ -z "$hits" ] || report "$path" "an address in 100.64.0.0/10" <<< "$hits"

          # An address at a domain this tree does not already use. The
          # dynamic DNS module lists its providers' protocol endpoints, which
          # share the shape of an address.
          if [ "$path" != modules/services/ddns.nix ]; then
            hits=$(grep -InoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[a-z]{2,}' "$file" |
              grep -vE '@([a-z0-9-]+\.)*example\.(com|org|net)$' |
              grep -vE '@(openssh\.com|libssh\.org|cloudflare\.com|raymondhill\.net|kagi\.com)$' |
              # The DDNS page names this inadyn provider, not an e-mail address.
              grep -vE '^[0-9]+:ipv6@dynv6\.com$' |
              grep -vE '\.service$' || true)
            [ -z "$hits" ] || report "$path" "an e-mail address outside example.com" <<< "$hits"
          fi
        }

        case "''${1:-}" in
          -)
            cat > "$work/stdin"
            scan "''${2:-standard input}" "$work/stdin"
            ;;
          "")
            while IFS= read -r -d "" f; do
              git show ":$f" > "$work/staged" 2>/dev/null || continue
              scan "$f" "$work/staged"
            done < <(git diff --cached --name-only --diff-filter=ACMR -z)
            ;;
          *)
            for f in "$@"; do
              [ -f "$f" ] && scan "$f" "$f"
            done
            ;;
        esac

        [ "$fail" -eq 0 ] || exit 1
      '';
    };

    # module-coverage reads the branch against its fork point from main and
    # says when a module changed while no page under docs/src or no check
    # under flake/checks did. It is a reminder for whoever is finishing the
    # branch and is not a commit hook, since a module and its check land as
    # separate commits. The branch to compare against is the first argument,
    # then OTHRYS_COVERAGE_BASE, then main, which serves a branch stacked on
    # another. Run from a repository root.
    moduleCoverage = pkgs.writeShellApplication {
      name = "module-coverage";
      runtimeInputs = [pkgs.gnugrep pkgs.gnused pkgs.coreutils pkgs.git];
      text = ''
        base=$(git merge-base HEAD "''${1:-''${OTHRYS_COVERAGE_BASE:-main}}" 2>/dev/null || echo HEAD)
        changed=$({
          git diff --name-only "$base"
          git ls-files --others --exclude-standard
        } | sort -u)

        modules=$(grep -E '^modules/.*\.nix$' <<< "$changed" || true)
        if [ -z "$modules" ]; then
          echo "module-coverage: no module changed since $base"
          exit 0
        fi

        missing=0
        if ! grep -qE '^docs/src/' <<< "$changed"; then
          missing=1
          echo "module-coverage: a module changed and no page under docs/src did"
        fi
        if ! grep -qE '^flake/checks/' <<< "$changed"; then
          missing=1
          echo "module-coverage: a module changed and no check under flake/checks did"
        fi
        if [ "$missing" -eq 1 ]; then
          echo "changed modules:"
          printf '%s\n' "$modules" | sed 's/^/  /'
          exit 1
        fi
        echo "module-coverage: ok"
      '';
    };

    # check-one builds a single named check, one at a time. Evaluating every
    # check of this flake at once has exhausted a workstation's memory, so the
    # build runs under one job and inside a memory-capped scope where the user
    # manager can make one, and a second call fails while the first holds the
    # lock. It is a store path, so nothing a session edits can change what it
    # runs. nix and systemd-run come from the caller's PATH.
    checkOne = pkgs.writeShellApplication {
      name = "check-one";
      runtimeInputs = [pkgs.util-linux pkgs.coreutils];
      text = ''
        name=''${1:-}
        if ! [[ $name =~ ^[a-z0-9][a-z0-9-]*$ ]] || [ $# -ne 1 ]; then
          echo "usage: check-one <check name>, as listed in flake/checks/default.nix" >&2
          exit 2
        fi

        jobs=''${OTHRYS_CHECK_JOBS:-1}
        cores=''${OTHRYS_CHECK_CORES:-4}
        memory=''${OTHRYS_CHECK_MEMORY:-16G}

        exec 9> "''${XDG_RUNTIME_DIR:-/tmp}/othrys-check-one.lock"
        if ! flock -n 9; then
          echo "check-one: another check is running, wait for it to finish" >&2
          exit 75
        fi

        system=$(nix eval --raw --impure --expr builtins.currentSystem)
        build=(nix build --no-link --print-build-logs --max-jobs "$jobs" --cores "$cores" ".#checks.$system.$name")
        if systemd-run --user --scope --quiet true 2> /dev/null; then
          systemd-run --user --scope --quiet -p "MemoryMax=$memory" -p MemorySwapMax=2G "''${build[@]}"
        else
          "''${build[@]}"
        fi
        echo "check-one: $name passed"
      '';
    };

    # The validator the opencode-config check runs (./opencode-config.py).
    opencodeConfig = pkgs.writeShellApplication {
      name = "opencode-config";
      runtimeInputs = [(pkgs.python3.withPackages (ps: [ps.pyyaml]))];
      text = ''
        exec python3 ${./opencode-config.py} "$@"
      '';
    };

    # portableHooks suit any Nix repository. repositoryHooks read this
    # repository's own tree, its contract prose, its module layout and its doc
    # anchors, and fail in any other. A flake that re-exports the dev shell
    # therefore takes devShells.consumer, which installs the portable set only.
    portableHooks = {
      treefmt = {
        enable = true;
        package = config.treefmt.build.wrapper;
      };
      statix.enable = true;
      deadnix.enable = true;
      commitizen.enable = true;

      # contract-guards covers where a secret may be referenced. This covers
      # content, scanning what is staged for anything shaped like a key or a
      # token before it reaches a public history.
      gitleaks = {
        enable = true;
        name = "gitleaks";
        entry = "${pkgs.gitleaks}/bin/gitleaks git --pre-commit --staged --redact --no-banner";
        pass_filenames = false;
      };
    };

    repositoryHooks = {
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
      hygiene-scan = {
        enable = true;
        name = "hygiene-scan";
        entry = "${hygieneScan}/bin/hygiene-scan";
        pass_filenames = true;
      };
    };

    # x86_64-linux runs every check. Any other system keeps the host
    # evaluations that hold no platform-bound package, which is what shows the
    # module tree evaluates there. The VM tests need a hypervisor for that
    # system, the desktop fixtures pull x86-only packages such as Steam, the
    # template names x86_64-linux itself, and the lint checks do not vary by
    # platform.
    portableChecks = [
      "eval-host-min"
      "eval-host-headless"
      "eval-host-server"
      "eval-host-anonymous"
      "eval-host-server-account"
      "eval-default"
      "eval-host-hardening"
      "eval-host-hardening-hibernate"
      "eval-bootloader"
      "eval-traefik"
      "eval-ssh"
      "eval-dev-shells"
    ];
    onThisSystem = all:
      if system == "x86_64-linux"
      then all
      else inputs.nixpkgs.lib.filterAttrs (name: _: builtins.elem name portableChecks) all;
  in {
    # Handed to ../dev-shells.nix as module arguments. It cannot read them off
    # config.checks, which holds no pre-commit-check on a system other than
    # x86_64-linux.
    _module.args = {
      inherit portableHooks repositoryHooks;
      # The three commands an agent session runs in place of bare nix builds
      # (see ../dev-shells.nix and AGENTS.md).
      agentTools = [hygieneScan moduleCoverage checkOne];
    };

    # ANCHOR: checks
    # Checks are split into two tiers. The GitHub workflow runs CORE on every PR
    # and EXTENDED only on main + manual dispatch (see .github/workflows).
    # `nix flake check` locally still runs all of them.
    checks = onThisSystem {
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
      # materializing a home-manager user. The host imports no Home Manager
      # module either, so a module that named the namespace fails here.
      #
      # A cheap representative slice runs here in CORE, one CLI module, one GUI
      # module, one desktop module, and vscode, which once read nixvim's build
      # product through config.home-manager and failed where that namespace is
      # absent, as it is on this host. The full set follows below, since a subset only proves
      # that a subset is guarded.
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

      # Every bootloader type with secureBoot off and on (see ./bootloader.nix).
      # Every other fixture carries its own GRUB and leaves the bootloader
      # module off, and the enable matrix lists it as an expected failure for
      # the same reason, so nothing else evaluates it.
      eval-bootloader = import ./bootloader.nix {
        inherit pkgs inputs system defaultModules bootCore;
      };

      # The hardening profile, read back rather than merely evaluated. Every
      # sysctl is compared with the value the profile documents, so a dropped or
      # retyped key fails here. The toplevel is forced as well, because
      # boot.kernel.sysctl rejects two definitions at one priority and NixOS
      # itself defines kernel.kptr_restrict and, under protectKernelImage,
      # kernel.kexec_load_disabled at mkDefault. The host's plain ptrace_scope
      # assignment has to win, and the router's strict rp_filter on its WAN
      # interface has to survive beside the profile's loose one.
      eval-host-hardening = let
        sysctl = hardenedHost.boot.kernel.sysctl;
        expected = {
          "kernel.kptr_restrict" = 2;
          "kernel.dmesg_restrict" = 1;
          "kernel.unprivileged_bpf_disabled" = 1;
          "net.core.bpf_jit_harden" = 2;
          "kernel.kexec_load_disabled" = 1;
          "net.ipv4.conf.all.rp_filter" = 2;
          "net.ipv4.conf.default.rp_filter" = 2;
          "net.ipv4.conf.all.accept_redirects" = 0;
          "net.ipv4.conf.default.accept_redirects" = 0;
          "net.ipv4.conf.all.secure_redirects" = 0;
          "net.ipv4.conf.default.secure_redirects" = 0;
          "net.ipv4.conf.all.send_redirects" = 0;
          "net.ipv4.conf.default.send_redirects" = 0;
          "net.ipv6.conf.all.accept_redirects" = 0;
          "net.ipv6.conf.default.accept_redirects" = 0;
          "net.ipv4.conf.all.accept_source_route" = 0;
          "net.ipv4.conf.default.accept_source_route" = 0;
          "net.ipv6.conf.all.accept_source_route" = 0;
          "net.ipv6.conf.default.accept_source_route" = 0;
          "net.ipv4.tcp_syncookies" = 1;
          "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
          "net.ipv4.tcp_rfc1337" = 1;
          "fs.suid_dumpable" = 0;
          "fs.protected_fifos" = 2;
          "fs.protected_regular" = 2;
          "vm.unprivileged_userfaultfd" = 0;
          "dev.tty.ldisc_autoload" = 0;
          "dev.tty.legacy_tiocsti" = 0;
          "kernel.perf_event_paranoid" = 2;
        };
        sandbox = (import ../../modules/lib/sandbox.nix).baseline;
      in
        mkExpectations "othrys-eval-host-hardening" (
          inputs.nixpkgs.lib.mapAttrs' (key: value:
            inputs.nixpkgs.lib.nameValuePair "sysctl ${key} is ${toString value}" ((sysctl.${key} or null) == value))
          expected
          // {
            "the hardened host evaluates" = hardenedHost.system.build.toplevel.drvPath != null;
            "the profile adds its kernel parameters" = builtins.all (p: builtins.elem p hardenedHost.boot.kernelParams) ["slab_nomerge" "page_alloc.shuffle=1" "vsyscall=none"];
            "the sandbox baseline hides the clock, the host name, the kernel log and other processes" = sandbox.ProtectClock && sandbox.ProtectHostname && sandbox.ProtectKernelLogs && sandbox.ProtectProc == "invisible" && sandbox.ProcSubset == "pid";
            "the sandbox baseline keeps mounts, IPC and new files private" = sandbox.PrivateMounts && sandbox.RemoveIPC && sandbox.UMask == "0077";
            "a plain host assignment of kernel.yama.ptrace_scope wins" = sysctl."kernel.yama.ptrace_scope" == 0;
            "security.lockKernelModules is set" = hardenedHost.security.lockKernelModules;
            "security.protectKernelImage is set" = hardenedHost.security.protectKernelImage;
            "Tailscale keeps the firewall reverse path check loose" = hardenedHost.networking.firewall.checkReversePath == "loose";
            "the hardened router evaluates" = hardenedRouter.system.build.toplevel.drvPath != null;
            "the router's rp_filter on all wins over the profile, at 0" = hardenedRouter.boot.kernel.sysctl."net.ipv4.conf.all.rp_filter" == 0;
            "the router keeps loose rp_filter on default" = hardenedRouter.boot.kernel.sysctl."net.ipv4.conf.default.rp_filter" == 2;
            "the router keeps strict rp_filter on its WAN interface" = hardenedRouter.boot.kernel.sysctl."net.ipv4.conf.wan0.rp_filter" == 1;
          }
        );

      # protectKernelImage disables hibernation, so the profile has to refuse a
      # host configured to hibernate, by either signal it reads. The last
      # expectation keeps the assertion from firing on a host that does not.
      eval-host-hardening-hibernate = let
        needle = "othrys.system.hardening.protectKernelImage";
      in
        mkExpectations "othrys-eval-host-hardening-hibernate" {
          "boot.resumeDevice is rejected" = rejectedWith needle (hibernatingHost {boot.resumeDevice = "/dev/disk/by-label/swap";});
          "a resume= kernel parameter is rejected" = rejectedWith needle (hibernatingHost {boot.kernelParams = ["resume=LABEL=swap"];});
          "a host that does not hibernate is accepted" = !rejectedWith needle hardenedHost;
        };

      eval-impermanence = import ./impermanence-eval.nix {inherit impermanenceModules hostConfig mkExpectations rejectedWith bootBase diskoModules;};

      # A host with no upstream module at all, a host that imports each
      # export, and a host built from the aggregate (see
      # ./exports-optional-eval.nix).
      eval-optional-exports = import ./exports-optional-eval.nix {
        inherit inputs system impermanenceModules hostEval mkExpectations rejectedWith bootBase functioningHost diskoModules secretsModules stylixModules;
      };

      # What the app and desktop modules persist, read back on an impermanence
      # host without a managed account and on one with (see ./persistence-eval.nix).
      eval-persistence = import ./persistence-eval.nix {inherit impermanenceModules hostConfig mkExpectations bootBase functioningHost appDesktopModules;};
      # What the service modules persist under impermanence (see ./service-state-eval.nix).
      eval-service-state = import ./service-state-eval.nix {inherit impermanenceModules hostConfig mkExpectations bootBase;};

      eval-lock = import ./lock.nix {inherit hostConfig mkExpectations rejectedWith functioningHost;};
      eval-login = import ./login.nix {inherit hostConfig mkExpectations rejectedWith functioningHost;};

      # What the desktop modules, kitty and ghostty write (see ./desktop-eval.nix).
      eval-desktop = import ./desktop-eval.nix {
        inherit (inputs.nixpkgs) lib;
        inherit hostConfig mkExpectations rejectedWith bootBase functioningHost stylixModules;
      };

      # What the Vicinae module writes, persists and refuses, and the launcher
      # chord on both compositors (see ./vicinae-eval.nix).
      eval-vicinae = import ./vicinae-eval.nix {
        inherit (inputs.nixpkgs) lib;
        inherit impermanenceModules stylixModules hostConfig mkExpectations rejectedWith bootCore functioningHost accountNoHomeManager;
      };

      # The Secret Service provider each keyring setting selects, and what the
      # module refuses (see ./keyring-eval.nix).
      eval-keyring = import ./keyring-eval.nix {
        inherit (inputs.nixpkgs) lib;
        inherit impermanenceModules hostConfig mkExpectations rejectedWith bootBase functioningHost accountNoHomeManager;
      };

      # The theme interface with and without the Stylix adapter (see
      # ./theme-eval.nix).
      eval-theme = import ./theme-eval.nix {
        inherit (inputs.nixpkgs) lib;
        inherit hostConfig mkExpectations rejectedWith functioningHost stylixModules;
      };

      # The wallpaper daemon's configuration for each form of
      # othrys.theme.wallpaper.source (see ./wallpaper-eval.nix).
      eval-wallpaper = import ./wallpaper-eval.nix {
        inherit (inputs.nixpkgs) lib;
        inherit hostConfig mkExpectations rejectedWith bootBase functioningHost stylixModules;
      };

      # Every conflict and dependency assertion that takes two modules or
      # two options to fire (see ./pairs.nix).
      eval-pairs = import ./pairs.nix {inherit impermanenceModules hostConfig mkExpectations rejectedWith bootBase functioningHost secretsModules;};

      # Three clauses of the consumer contract, read back from evaluation
      # (see ./contract-eval.nix).
      eval-contract = import ./contract-eval.nix {
        inherit impermanenceModules homeModules inputs hostEval mkExpectations templateHost moduleHelpers;
        inherit functioningHost accountNoHomeManager appDesktopModules serverModules;
      };

      # Where the modules take ashell, Hyprland, nixvim and nix-index-database
      # from, on a host that is handed no specialArgs (see ./inputs-eval.nix).
      eval-inputs = import ./inputs-eval.nix {
        inherit inputs system defaultModules secretsModules functioningHost mkExpectations;
      };

      # The check names in .github/workflows/build.yml, held to the checks
      # defined here (see ./ci-coverage.nix).
      ci-coverage = import ./ci-coverage.nix {inherit pkgs inputs system;};

      # The same contract over every app and desktop module that writes per-user
      # configuration. It is an evaluation, and only the wrapper that records
      # the derivation path is built, so it runs in CORE beside
      # eval-persistence, which evaluates the same module set twice. It is the
      # only fixture that proves the claim for all of them rather than for four.
      eval-host-app-no-hm-full = mkHostEval "othrys-eval-host-app-no-hm-full" [
        accountNoHomeManager
        appDesktopModules
      ];

      # EXTENDED, heavy, one runner each

      # Whole-tree evaluation over the minimal host plus Stylix through the
      # adapter and the mangohud settings merge (Stylix themes mangohud too, and
      # this pairing caught the mangohud x Stylix conflict). Heavier GUI apps
      # (floorp, vesktop) are left out so this doesn't pull a browser/Electron
      # closure. Their merges are trivial `//` unions covered by plain eval + parse.
      eval-default = mkHostEval "othrys-eval-default" [
        functioningHost
        stylixModules
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
      # defaults working for the whole desktop stack. Stylix is on through the
      # adapter here, so both compositors are evaluated beside its targets.
      eval-host-desktop = mkHostEval "othrys-eval-host-desktop" [
        functioningHost
        stylixModules
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
          othrys.desktop.nightLight = {
            enable = true;
            latitude = 0.0;
            longitude = 0.0;
          };
          othrys.hardware.scanner.enable = true;
          # Pins two failure classes, an unfree package inside home-manager
          # (needs useGlobalPkgs to see nixpkgs.config.allowUnfree) and a
          # dereference across two Home Manager modules (vscode reads nixvim's
          # package inside the user's configuration).
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

      # Niri-only desktop with ashell. Login starts niri-session directly and
      # defaultDesktop stays UNSET, pinning that sessionCommand doesn't force
      # the uwsm-path option. No Stylix module is imported, so niri and the bar
      # take their colours from othrys.theme alone.
      eval-host-desktop-niri = mkHostEval "othrys-eval-host-desktop-niri" [
        functioningHost
        {
          othrys.desktop.compositors.niri.enable = true;
          othrys.desktop.ashell.enable = true;
          othrys.desktop.login = {
            enable = true;
            sessionCommand = "niri-session";
          };
        }
      ];

      # The export list, held to the module tree (see ./exports-eval.nix).
      eval-exports = import ./exports-eval.nix {inherit pkgs inputs moduleHelpers;};

      # The default template, as templateHost above instantiates it. A
      # template that stops matching the consumer contract, or the required
      # options, fails here instead of in a new user's first build.
      #
      # The host the template describes also has to be one somebody can log
      # in to. It ships a bootstrap hash rather than a secrets path, since no
      # secrets module is enabled there and a path under /run/secrets/ is
      # installed after the account is created. Both facts are read back.
      #
      # The shipped hash is a placeholder, and NixOS says so with its "may be
      # invalid" notice, which is the right message for a template built
      # unedited. That one warning is expected, and any other means an othrys
      # module objects to the template as shipped.
      eval-template = let
        template = templateHost.config;
        account = template.users.users.${template.othrys.system.user.name};
      in
        pkgs.runCommand "othrys-eval-template" {
          drv = builtins.unsafeDiscardStringContext template.system.build.toplevel.drvPath;
          passwordFile = toString account.hashedPasswordFile;
          hasBootstrapHash =
            if account.initialHashedPassword != null && account.initialHashedPassword != ""
            then "1"
            else "0";
          warningCount = toString (builtins.length (builtins.filter (w: !inputs.nixpkgs.lib.hasInfix "password hash" w) template.warnings));
        } ''
          [ -z "$passwordFile" ] || {
            echo "template: passwordFile is set to $passwordFile, but the template enables no secrets module" >&2
            exit 1
          }
          [ "$hasBootstrapHash" = 1 ] || {
            echo "template: initialHashedPassword is unset, so the account has no password" >&2
            exit 1
          }
          [ "$warningCount" = 0 ] || {
            echo "template: evaluates with $warningCount warning(s)" >&2
            exit 1
          }
          echo "$drv" > "$out"
        '';

      # The dev shells, held to the hooks they claim to install. The default
      # shell has to match pre-commit-check, and the consumer shell has to
      # carry no hook that reads this repository's own tree. It is also the
      # one check that evaluates the dev shells on every system.
      eval-dev-shells = let
        inherit (inputs.nixpkgs) lib;
        default = config.devShells.default.hookIds;
        consumer = config.devShells.consumer.hookIds;
        portable = builtins.attrNames portableHooks;
        repository = builtins.attrNames repositoryHooks;
      in
        mkExpectations "othrys-eval-dev-shells" {
          "the default shell installs every portable hook" = lib.all (hook: builtins.elem hook default) portable;
          "the default shell installs every repository hook" = lib.all (hook: builtins.elem hook default) repository;
          "the default shell installs what pre-commit-check runs and nothing else" = default == lib.sort builtins.lessThan (portable ++ repository);
          "the consumer shell installs every portable hook" = lib.all (hook: builtins.elem hook consumer) portable;
          "the consumer shell installs no repository hook" = !(lib.any (hook: builtins.elem hook consumer) repository);
          "the four repository hooks are the ones expected" = repository == ["comment-hygiene" "contract-guards" "contract-mirror" "hygiene-scan"];
          "the hygiene hook scans filenames in a clean CI checkout" = repositoryHooks.hygiene-scan.pass_filenames;
        };

      # Start-up defaults of Suricata and CrowdSec (see ./router-services.nix).
      eval-router-services = import ./router-services.nix {inherit hostConfig mkExpectations rejectedWith bootBase;};
      eval-router = import ./router-eval.nix {inherit hostConfig hostEval mkExpectations rejectedWith bootBase;};
      eval-headscale = import ./headscale-eval.nix {inherit impermanenceModules hostConfig mkExpectations rejectedWith bootBase;};
      eval-tailscale = import ./tailscale-eval.nix {inherit hostConfig mkExpectations bootBase;};
      eval-exposure = import ./exposure-eval.nix {inherit impermanenceModules hostConfig mkExpectations rejectedWith bootBase functioningHost;};
      eval-claude-code = import ./claude-code-eval.nix {inherit impermanenceModules hostConfig mkExpectations rejectedWith functioningHost bootBase inputs;};

      eval-opencode = import ./opencode-eval.nix {inherit hostConfig mkExpectations functioningHost inputs;};

      # The committed OpenCode configuration, read as files. Every skill name
      # matches its directory, every agent and command carries a description,
      # and every agent a file names exists (see ./opencode-config.py).
      opencode-config =
        pkgs.runCommand "othrys-opencode-config" {
          nativeBuildInputs = [opencodeConfig hygieneScan moduleCoverage pkgs.git pkgs.bun (pkgs.python3.withPackages (ps: [ps.pyyaml]))];
        } ''
          opencode-config ${inputs.self}
          python3 ${./opencode-regressions.py} ${inputs.self}
          OTHRYS_ROOT=${inputs.self} bun test ${./othrys-plugin.test.js}
          touch $out
        '';
      # What the gh module renders, wraps and pre-approves (see ./gh-eval.nix).
      eval-gh = import ./gh-eval.nix {
        inherit (inputs.nixpkgs) lib;
        inherit hostConfig mkExpectations functioningHost bootBase;
      };
      eval-k3s = import ./k3s-eval.nix {inherit impermanenceModules hostConfig hostEval mkExpectations rejectedWith bootBase;};
      eval-pam = import ./pam-eval.nix {inherit hostConfig mkExpectations rejectedWith functioningHost;};
      eval-containers = import ./containers-eval.nix {inherit hostConfig mkExpectations rejectedWith functioningHost;};
      eval-nix = import ./nix-eval.nix {inherit hostConfig mkExpectations rejectedWith bootBase functioningHost inputs;};
      eval-grafana = import ./grafana-eval.nix {inherit hostConfig mkExpectations rejectedWith functioningHost;};
      eval-listen = import ./listen-eval.nix {inherit hostConfig mkExpectations functioningHost;};
      eval-shell = import ./shell-eval.nix {inherit hostConfig mkExpectations bootBase functioningHost;};
      eval-floorp = import ./floorp-eval.nix {inherit hostConfig mkExpectations functioningHost;};
      eval-chromium = import ./chromium-eval.nix {
        inherit (inputs.nixpkgs) lib;
        inherit pkgs hostConfig mkExpectations rejectedWith functioningHost bootBase bootCore homeModules accountNoHomeManager;
      };

      # Which binaries nixvim and vscode take from the language registry (see
      # ./languages-eval.nix).
      eval-languages = import ./languages-eval.nix {
        inherit (inputs.nixpkgs) lib;
        inherit hostConfig mkExpectations functioningHost;
      };

      # What the hardware, mount and disk modules write (see ./hardware-eval.nix).
      # What the GameMode, Steam and ntsync modules grant the user (see ./gaming-eval.nix).
      eval-gaming = import ./gaming-eval.nix {inherit hostConfig mkExpectations rejectedWith bootBase functioningHost inputs;};

      eval-hardware = import ./hardware-eval.nix {inherit hostConfig mkExpectations rejectedWith bootBase functioningHost diskoModules inputs;};

      # What the smaller service modules pass upstream and refuse (see ./services-eval.nix).
      eval-services = import ./services-eval.nix {inherit impermanenceModules hostConfig mkExpectations rejectedWith functioningHost inputs;};
      eval-auto-upgrade = import ./auto-upgrade-eval.nix {inherit hostConfig mkExpectations rejectedWith functioningHost;};

      # What the option types and the named assertions refuse (see ./types-eval.nix).
      eval-types = import ./types-eval.nix {inherit impermanenceModules homeModules hostConfig mkExpectations rejectedWith bootBase functioningHost inputs;};

      # Which NVIDIA driver and kernel modules a host gets (see ./nvidia.nix).
      eval-nvidia = import ./nvidia.nix {inherit hostConfig mkExpectations functioningHost;};

      # What the RustDesk module persists and launches (see ./rustdesk.nix).
      eval-rustdesk = import ./rustdesk.nix {inherit impermanenceModules hostConfig mkExpectations functioningHost;};

      # The SSH known hosts and client defaults (see ./ssh.nix).
      eval-ssh = import ./ssh.nix {inherit hostConfig mkExpectations functioningHost;};

      # The SSH server's ports, firewall, jail and hardened defaults (see ./ssh-eval.nix).
      eval-ssh-settings = import ./ssh-eval.nix {inherit hostConfig mkExpectations functioningHost;};

      # The Traefik TLS floor and header defaults (see ./traefik.nix).
      eval-traefik = import ./traefik.nix {inherit hostConfig mkExpectations bootBase;};

      # EXTENDED. The ashell bar config for a desktop and a laptop (see ./ashell.nix).
      eval-ashell = import ./ashell.nix {
        inherit (inputs.nixpkgs) lib;
        inherit hostConfig mkExpectations functioningHost;
      };

      # EXTENDED. Enable-with-defaults matrix (see ./enable-matrix.nix).
      enable-matrix = import ./enable-matrix.nix {
        inherit impermanenceModules pkgs inputs system defaultModules stylixModules diskoModules secretsModules bootCore bootBase functioningHost;
      };

      # EXTENDED. Runtime VM tests, one file each.
      integration-test = import ./integration.nix {inherit pkgs inputs;};
      listeners-test = import ./listeners.nix {inherit pkgs inputs;};
      restic-test = import ./restic.nix {inherit pkgs inputs hostConfig rejectedWith bootBase;};
      crowdsec-test = import ./crowdsec.nix {inherit pkgs inputs;};
      headscale-test = import ./headscale.nix {inherit pkgs inputs;};
      impermanence-reboot-test = import ./impermanence-reboot.nix {inherit pkgs inputs;};
      impermanence-wipe-test = import ./impermanence-wipe.nix {inherit pkgs inputs;};
      router-test = import ./router.nix {inherit pkgs inputs;};
      router-ips-test = import ./router-ips.nix {inherit pkgs inputs;};
      auto-upgrade-test = import ./auto-upgrade.nix {inherit pkgs inputs;};
      wallpaper-test = import ./wallpaper.nix {inherit pkgs inputs;};
      keyring-test = import ./keyring.nix {inherit pkgs inputs;};

      # EXTENDED. The onboarding script's dry run in a VM (see ./yubikey-onboard.nix).
      yubikey-onboard-dry-run = import ./yubikey-onboard.nix {
        inherit pkgs;
        package = config.packages.yubikey-onboard;
      };

      # CORE. The onboarding script's package builds. writeShellApplication
      # runs shellcheck and `bash -n` over the script at build time, and
      # `nix flake check` evaluates a package without building it, so this
      # check is the only place either runs.
      yubikey-onboard-builds = config.packages.yubikey-onboard;

      # CORE. Pre-commit hooks check (treefmt formats, statix and deadnix lint,
      # comment-hygiene enforces the CONTRIBUTING.md comment conventions).
      pre-commit-check = inputs.git-hooks.lib.${system}.run {
        src = inputs.self;
        hooks = portableHooks // repositoryHooks;
      };

      # CORE. The hook above only sees what one commit stages. This scans every
      # tracked file, so a secret that arrived any other way still fails CI.
      secret-scan =
        pkgs.runCommand "othrys-secret-scan" {
          nativeBuildInputs = [pkgs.gitleaks];
        } ''
          gitleaks dir ${inputs.self} --redact --no-banner
          touch $out
        '';

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

      # CORE. Every include and every relative link in docs/src resolves. mdbook
      # exits 0 on an include it cannot read, so a renamed anchor or a moved
      # file leaves a gap in the rendered page unless something else fails. The
      # fixtures run first and show that each broken case does fail. The
      # options reference is generated, so links to it are accepted here and
      # resolved in the docs check below, which has the file.
      docs-includes =
        pkgs.runCommand "othrys-docs-includes" {
          nativeBuildInputs = [docsIncludes docsIncludesFixtures];
        } ''
          docs-includes-fixtures
          cd ${inputs.self}
          docs-includes docs/src --generated reference/options.md
          touch $out
        '';

      # CORE. The book builds. The generated options reference is injected
      # first (see flake/docs-options.nix), then the resolver runs over the
      # complete source and fails the build on a missing include, anchor, page
      # or heading before mdbook renders anything.
      docs = pkgs.stdenv.mkDerivation {
        name = "othrys-docs";
        src = inputs.self;
        nativeBuildInputs = [pkgs.mdbook docsIncludes];
        buildPhase = ''
          install -m644 ${config.packages.options-doc} docs/src/reference/options.md
          docs-includes docs/src
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
