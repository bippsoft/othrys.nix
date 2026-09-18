# modules/system/auto-upgrade.nix
# Unattended flake upgrades for headless hosts, pulling the host configuration
# flake on a schedule, switch, optionally reboot inside a window. Failures push
# through othrys-notify when the notify module is enabled. An upgrade that
# silently stops applying is how fleets rot.
#
# With verify on, a oneshot unit fetches the repository first and only hands
# the rebuild a commit whose signature comes from a configured key.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.system.autoUpgrade;
  sandbox = import ../lib/sandbox.nix;
  notifyEnabled = config.othrys.services.notify.enable;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  verifyUnit = "othrys-auto-upgrade-verify";
  stateDir = "/var/lib/${verifyUnit}";
  checkoutDir = "${stateDir}/checkout";
  lastVerifiedFile = "${stateDir}/last-verified";

  openpgp = cfg.verify.format == "openpgp";

  # Replacing flake.lock after verification would build inputs the signature
  # never covered.
  lockMutatingFlags = ["--update-input" "--recreate-lock-file" "--override-input"];

  # The only git configuration the unit reads. Interpolating a key file copies
  # a path literal into the store and leaves a runtime path string as it is.
  # Only the configured format gets a verifier, so a signature in the other
  # format has nothing that could accept it.
  gitConfig = pkgs.writeText "${verifyUnit}-gitconfig" (lib.generators.toGitINI {
    gpg =
      if openpgp
      then {program = "${pkgs.gnupg}/bin/gpg";}
      else {
        ssh = {
          program = "${config.programs.ssh.package}/bin/ssh-keygen";
          allowedSignersFile = "${cfg.verify.allowedSigners}";
        };
      };
  });

  verifyScript = pkgs.writeShellApplication {
    name = verifyUnit;
    runtimeInputs =
      [pkgs.gitMinimal pkgs.coreutils pkgs.gnugrep pkgs.gnused]
      ++ lib.optional openpgp pkgs.gnupg;
    text = ''
      url=${lib.escapeShellArg cfg.verify.url}
      repo="$STATE_DIRECTORY/repo.git"
      checkout=${lib.escapeShellArg checkoutDir}
      last_file=${lib.escapeShellArg lastVerifiedFile}

      export GIT_CONFIG_NOSYSTEM=1
      export GIT_CONFIG_GLOBAL=${gitConfig}
      export GIT_TERMINAL_PROMPT=0

      fail() {
        echo "${verifyUnit}: $1" >&2
        exit 1
      }

      ${
        if openpgp
        then ''
          armor="-----BEGIN PGP SIGNATURE-----"
          has_good_signature() {
            grep -q '^\[GNUPG:\] GOODSIG ' <<<"$1" &&
              grep -q '^\[GNUPG:\] VALIDSIG ' <<<"$1"
          }
          keys=(${lib.escapeShellArgs (map (key: "${key}") cfg.verify.publicKeys)})

          # A keyring that exists only for this run and holds only the
          # configured keys, so a good signature can only come from one of them.
          export GNUPGHOME="$RUNTIME_DIRECTORY/gnupg"
          mkdir -m 700 "$GNUPGHOME"
          for key in "''${keys[@]}"; do
            gpg --batch --quiet --import "$key" ||
              fail "importing the public key $key failed"
          done
        ''
        else ''
          armor="-----BEGIN SSH SIGNATURE-----"
          has_good_signature() {
            grep -q '^Good "git" signature for ' <<<"$1"
          }
        ''
      }

      # verify_object <commit|tag> <object> <name used in messages>
      verify_object() {
        local kind="$1" object="$2" name="$3" signature status

        if [ "$kind" = commit ]; then
          signature="$(git -C "$repo" cat-file commit "$object" |
            sed -n '1,/^$/ s/^gpgsig\(-sha256\)\? //p')"
        else
          signature="$(git -C "$repo" cat-file tag "$object" |
            sed -n '/^-----BEGIN [A-Z ]*-----$/p' | tail -n 1)"
        fi
        case "$signature" in
          "$armor") ;;
          "") fail "$kind $name is not signed" ;;
          *) fail "$kind $name is not signed in the ${cfg.verify.format} format" ;;
        esac

        # The exit status alone is not enough. The status text has to show a
        # good signature that the configured verifier matched to a listed key.
        if ! status="$(git -C "$repo" "verify-$kind" --raw "$object" 2>&1)" ||
          ! has_good_signature "$status"; then
          echo "$status" >&2
          fail "$kind $name has no good signature from a configured key"
        fi
      }

      [ -d "$repo" ] || git init --quiet --bare "$repo"

      ${
        if cfg.verify.mode == "commit"
        then ''
          ref=${lib.escapeShellArg cfg.verify.ref}
          git -C "$repo" fetch --quiet --force --no-tags "$url" \
            "+refs/heads/$ref:refs/candidate/head" ||
            fail "fetching the branch $ref from $url failed"
          new="$(git -C "$repo" rev-parse --verify 'refs/candidate/head^{commit}')"
          verify_object commit "$new" "$new"
        ''
        else ''
          pattern=${lib.escapeShellArg cfg.verify.tagPattern}
          git -C "$repo" fetch --quiet --force --prune --no-tags "$url" \
            '+refs/tags/*:refs/tags/*' ||
            fail "fetching tags from $url failed"
          tag="$(git -C "$repo" for-each-ref --count=1 --sort=-version:refname \
            --format='%(refname:strip=2)' "refs/tags/$pattern")"
          [ -n "$tag" ] || fail "no tag matching $pattern at $url"
          [ "$(git -C "$repo" cat-file -t "refs/tags/$tag")" = tag ] ||
            fail "tag $tag is lightweight and carries no signature"
          verify_object tag "refs/tags/$tag" "$tag"
          # The signature covers the name inside the tag object and not the
          # ref it was served under, so an old signed tag renamed to a higher
          # version is caught here.
          [ "$(git -C "$repo" cat-file tag "refs/tags/$tag" | sed -n '1,/^$/ s/^tag //p')" = "$tag" ] ||
            fail "tag $tag was signed under a different name"
          new="$(git -C "$repo" rev-parse --verify "refs/tags/$tag^{commit}")"
        ''
      }

      if [ -s "$last_file" ]; then
        last="$(cat "$last_file")"
        git -C "$repo" merge-base --is-ancestor "$last" "$new" 2>/dev/null ||
          fail "commit $new does not descend from the last verified commit $last, delete $last_file after a deliberate history rewrite"
      fi

      # refs/verified/head keeps the last verified commit alive across a forced
      # push, and it is the only ref the checkout ever fetches, so unverified
      # objects never reach the directory the rebuild reads.
      git -C "$repo" update-ref refs/verified/head "$new"
      [ -d "$checkout/.git" ] || git init --quiet "$checkout"
      git -C "$checkout" fetch --quiet --force --no-tags "$repo" \
        '+refs/verified/head:refs/verified/head'
      git -C "$checkout" checkout --quiet --force --detach "$new"
      git -C "$checkout" clean --quiet -ffdx

      printf '%s\n' "$new" > "$last_file.tmp"
      mv "$last_file.tmp" "$last_file"
      echo "${verifyUnit}: verified $new"
    '';
  };
in {
  # ANCHOR: auto-upgrade-options
  options.othrys.system.autoUpgrade = {
    enable = lib.mkEnableOption "unattended nixos-rebuild from the host configuration flake";

    flake = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "github:example/hosts";
      description = "Flake URI the host upgrades from (the host configuration flake, not this library). Identity-shaped, set from the consuming host. Private repos need fetch credentials (e.g. a netrc via secrets). Nothing checks a signature on this path. Leave it null and use verify for that.";
    };

    dates = lib.mkOption {
      type = lib.types.str;
      default = "04:00";
      description = "systemd calendar expression for the upgrade timer (daily at 04:00 by default, since servers want security fixes promptly).";
    };

    allowReboot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Reboot when the new generation requires it (kernel/systemd changes). Off by default, so enable deliberately with a rebootWindow.";
    };

    rebootWindow = lib.mkOption {
      type = lib.types.nullOr (lib.types.attrsOf lib.types.str);
      default = null;
      example = {
        lower = "03:00";
        upper = "05:00";
      };
      description = "Time window reboots are confined to (with allowReboot). Null reboots whenever the upgrade lands.";
    };

    randomizedDelaySec = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = "Random delay added to the timer so a fleet doesn't hit the flake host simultaneously.";
    };

    flags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra flags passed to nixos-rebuild.";
    };

    verify = {
      enable = lib.mkEnableOption "signature verification of the host configuration repository before every upgrade";

      url = lib.mkOption {
        type = lib.types.str;
        example = "https://example.com/alice/hosts.git";
        description = "Git URL the verify unit fetches. The fetch is anonymous, so the repository has to be readable without credentials.";
      };

      ref = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = "Branch followed in commit mode. Its tip has to carry a good signature.";
      };

      mode = lib.mkOption {
        type = lib.types.enum ["commit" "tag"];
        default = "commit";
        description = "What carries the signature. commit verifies the tip of ref with git verify-commit. tag takes the highest tag matching tagPattern by version sort, verifies it with git verify-tag and upgrades to the commit it points at, so an unsigned newer tag stops upgrades until it is removed.";
      };

      tagPattern = lib.mkOption {
        type = lib.types.str;
        default = "v*";
        description = "Glob selecting the tags considered in tag mode.";
      };

      format = lib.mkOption {
        type = lib.types.enum ["openpgp" "ssh"];
        default = "openpgp";
        description = "Signature format that is accepted. A signature in the other format fails verification.";
      };

      publicKeys = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [];
        example = lib.literalExpression "[./keys/alice.asc]";
        description = "ASCII-armoured OpenPGP public key files, used when format is openpgp. These are the only keys whose signatures pass. A path literal is copied into the store, while a string such as \"/run/secrets/signer.asc\" is read at run time.";
      };

      allowedSigners = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression "./keys/allowed_signers";
        description = "OpenSSH allowed signers file, used when format is ssh. Path literals and runtime path strings are handled as in publicKeys.";
      };

      attribute = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
        defaultText = lib.literalExpression "config.networking.hostName";
        description = "The nixosConfigurations attribute of the verified repository that the host builds.";
      };
    };
  };
  # ANCHOR_END: auto-upgrade-options

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = (cfg.flake != null) != cfg.verify.enable;
          message = "othrys.system.autoUpgrade: set exactly one upgrade source, either flake or verify.enable with verify.url. With verify on, the rebuild reads the verified checkout and flake has to stay null.";
        }
      ];

      system.autoUpgrade = {
        enable = true;
        inherit (cfg) dates allowReboot rebootWindow randomizedDelaySec flags;
        flake =
          if cfg.verify.enable
          then "git+file://${checkoutDir}#${cfg.verify.attribute}"
          else cfg.flake;
      };

      # A failed upgrade must reach a human (cross-module conditional, no
      # hard dependency on notify).
      systemd.services.nixos-upgrade = lib.mkIf notifyEnabled {
        onFailure = ["notify-failure@%n.service"];
      };
    }

    (lib.mkIf cfg.verify.enable {
      assertions = [
        {
          assertion = !openpgp || cfg.verify.publicKeys != [];
          message = "othrys.system.autoUpgrade.verify: format = \"openpgp\" needs at least one key file in publicKeys.";
        }
        {
          assertion = openpgp || cfg.verify.allowedSigners != null;
          message = "othrys.system.autoUpgrade.verify: format = \"ssh\" needs allowedSigners.";
        }
        {
          assertion = !(lib.any (flag: lib.any (bad: lib.hasInfix bad flag) lockMutatingFlags) cfg.flags);
          message = "othrys.system.autoUpgrade.verify: flags must not contain ${lib.concatStringsSep ", " lockMutatingFlags}. The verified signature covers flake.lock, and these flags replace locked inputs after verification.";
        }
      ];

      # Requires plus After means a failed verification fails the start job of
      # the upgrade, so the rebuild never runs against an unverified ref.
      systemd.services.nixos-upgrade = {
        requires = ["${verifyUnit}.service"];
        after = ["${verifyUnit}.service"];
      };

      # The unit parses data from the network, so it gets the notify-failure@
      # sandbox with two differences. It keeps a state and a runtime directory,
      # and it runs as root without capabilities instead of under DynamicUser.
      # The rebuild reads the checkout as root, and Nix refuses a git
      # repository owned by another user.
      systemd.services.${verifyUnit} = {
        description = "Verify the signature on the host configuration before an upgrade.";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        onFailure = lib.mkIf notifyEnabled ["notify-failure@%n.service"];
        serviceConfig =
          sandbox.baseline
          // {
            Type = "oneshot";
            ExecStart = lib.getExe verifyScript;
            StateDirectory = verifyUnit;
            RuntimeDirectory = verifyUnit;
            RuntimeDirectoryMode = "0700";
            RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
          };
      };

      # The last verified commit is what the rollback rule compares against,
      # so it has to survive the root wipe.
      environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
        directories = [
          {
            directory = stateDir;
            user = "root";
            group = "root";
            mode = "0755";
          }
        ];
      };
    })
  ]);
}
