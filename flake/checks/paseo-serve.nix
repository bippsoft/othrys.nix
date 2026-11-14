# flake/checks/paseo-serve.nix
# CORE. What the paseo serve script does when it runs, read back from a
# stand-in paseo-server and from the config.json it leaves behind. The
# script edits ~/.paseo/config.json with jq before the daemon starts, and
# whether it keeps the keys the daemon wrote, removes a stale plugin entry
# and refuses a file it cannot read exists only at run time. The script is
# taken from an evaluated host whose paseo package is a stand-in that prints
# its environment and exits 0, whose plugin is a stand-in directory and
# whose codex is a stand-in program. Other hosts turn the plugin off, set a
# password file or serve the web UI under listed hostnames, and a last one
# keeps the default package to show it holds the web UI. The host is a NixOS host on Linux and a nix-darwin host
# on a Mac, so the script is built for the system that runs it.
{
  pkgs,
  hostConfig,
  darwinConfig,
  bootBase,
  darwinBase,
}: let
  inherit (pkgs) lib;
  standIn = {pkgs, ...}: {
    othrys.apps.ai.codex.package = pkgs.writeShellApplication {
      name = "codex";
      text = "exit 0";
    };
    othrys.apps.ai.paseo = {
      package = pkgs.writeShellScriptBin "paseo-server" ''
        echo "PASEO_HOME=$PASEO_HOME"
        echo "PASEO_LISTEN=$PASEO_LISTEN"
        echo "PASEO_RELAY_ENABLED=$PASEO_RELAY_ENABLED"
        echo "PASEO_DIRENV_TRUST_WORKTREES=''${PASEO_DIRENV_TRUST_WORKTREES-unset}"
        echo "PATH=$PATH"
        echo "UMASK=$(umask)"
        echo "PASEO_WEB_UI_ENABLED=$PASEO_WEB_UI_ENABLED"
        echo "PASEO_HOSTNAMES=''${PASEO_HOSTNAMES-unset}"
        echo "PASEO_PASSWORD=''${PASEO_PASSWORD-unset}"
      '';
      direnv.package = pkgs.runCommand "paseo-direnv-standin" {} ''
        mkdir -p "$out"
        echo '{"name": "paseo-direnv"}' > "$out/package.json"
      '';
    };
  };
  paseoOn = {
    othrys.apps.ai = {
      codex.enable = true;
      paseo = {
        enable = true;
        service.enable = true;
      };
    };
  };
  direnvOff = {othrys.apps.ai.paseo.direnv.enable = false;};
  password = file: {othrys.apps.ai.paseo.passwordFile = file;};
  host = modules:
    if pkgs.stdenv.hostPlatform.isDarwin
    then darwinConfig ([darwinBase standIn paseoOn] ++ modules)
    else hostConfig ([bootBase standIn paseoOn] ++ modules);
  on = host [];
  # The package a host gets by default, with no stand-in, so the check holds
  # the web UI that webUi.enable serves to its source.
  defaultPackage =
    (
      if pkgs.stdenv.hostPlatform.isDarwin
      then darwinConfig [darwinBase paseoOn]
      else hostConfig [bootBase paseoOn]
    ).othrys.apps.ai.paseo.package;
  off = host [direnvOff];
  readable = host [(password "${pkgs.writeText "paseo-password" "example"}")];
  unreadable = host [(password "/var/empty/missing")];
  proxied = host [
    {
      othrys.apps.ai.paseo = {
        webUi.enable = true;
        hostnames = ["paseo.example.com" "code.example.com"];
      };
    }
  ];
in
  pkgs.runCommand "othrys-paseo-serve" {
    nativeBuildInputs = [pkgs.jq pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.diffutils];
  } ''
    set -euo pipefail
    serve=${on.othrys.internal.paseo.serve}
    serveOff=${off.othrys.internal.paseo.serve}
    servePassword=${readable.othrys.internal.paseo.serve}
    serveNoPassword=${unreadable.othrys.internal.paseo.serve}
    configOff=${off.othrys.internal.paseo.pluginConfig}
    serveProxied=${proxied.othrys.internal.paseo.serve}
    plugin=${on.othrys.apps.ai.paseo.direnv.package}
    launcher=${lib.getBin on.othrys.internal.agents.codex}/bin
    basePath=${pkgs.coreutils}/bin

    work=$(realpath "$TMPDIR")/work
    mkdir -p "$work"
    fail=0
    : > "$work/out"
    : > "$work/err"

    # run <home> <script> runs the script with HOME there, coreutils alone
    # on the PATH it inherits, as a unit's PATH would carry them, and the
    # umask a user manager gives its units.
    run() {
      status=0
      (umask 022 && env -i HOME="$1" PATH="$basePath" "$2") > "$work/out" 2> "$work/err" || status=$?
    }
    expect() {
      local label=$1
      shift
      if "$@"; then
        echo "ok: $label"
      else
        echo "FAILED: $label" >&2
        sed 's/^/  stdout: /' "$work/out" >&2
        sed 's/^/  stderr: /' "$work/err" >&2
        if [ -e "$home/.paseo/config.json" ]; then
          sed 's/^/  config.json: /' "$home/.paseo/config.json" >&2
        fi
        fail=1
      fi
    }
    exited() { [ "$status" = "$1" ]; }
    failed() { [ "$status" != 0 ]; }
    printed() { grep -qxF -e "$1" "$work/out"; }
    started() { grep -q -e '^PASEO_HOME=' "$work/out"; }
    notStarted() { ! started; }
    complained() { grep -qF -e "$1" "$work/err"; }
    config() { jq -e "$@" "$home/.paseo/config.json" > /dev/null; }
    mode() { [ "$(stat -c %a "$1")" = "$2" ]; }
    missing() { [ ! -e "$1" ]; }
    noTemporary() {
      local left
      left=$(find "$home/.paseo" -maxdepth 1 -name 'config.json.*' 2> /dev/null)
      [ -z "$left" ]
    }
    pathPrinted() { sed -n 's/^PATH=//p' "$work/out"; }
    pathStarts() { case "$(pathPrinted)" in "$1":*) return 0 ;; esac; return 1; }
    pathEnds() { case "$(pathPrinted)" in *:"$1") return 0 ;; esac; return 1; }
    pathHas() { pathPrinted | tr ':' '\n' | grep -q -e "$1"; }
    pathLacks() { ! pathHas "$1"; }

    # a. No config.json, with the plugin on.
    home=$work/a
    mkdir -p "$home"
    run "$home" "$serve"
    expect "the script starts paseo-server and it exits 0" exited 0
    expect "a missing config.json is created holding the plugin entry and nothing else" \
      config --arg p "$plugin" '. == {pluginsEnabled: true, plugins: {"paseo-direnv": {source: "directory", path: $p, enabled: true}}}'
    expect "~/.paseo is created at mode 700" mode "$home/.paseo" 700
    expect "the created config.json is at mode 600" mode "$home/.paseo/config.json" 600
    expect "no temporary file is left beside config.json" noTemporary
    expect "the daemon's home is ~/.paseo" printed "PASEO_HOME=$home/.paseo"
    expect "the daemon listens on 127.0.0.1:6767" printed "PASEO_LISTEN=127.0.0.1:6767"
    expect "the hosted relay is off" printed "PASEO_RELAY_ENABLED=false"
    expect "the plugin trusts identical worktree .envrc files" printed "PASEO_DIRENV_TRUST_WORKTREES=1"
    expect "the daemon's PATH starts with the codex launcher" pathStarts "$launcher"
    expect "the daemon's PATH holds direnv" pathHas '-direnv-[0-9.]*/bin$'
    expect "the daemon's PATH holds git" pathHas '-git-[0-9.]*/bin$'
    expect "the daemon's PATH ends with the one it inherited" pathEnds "$basePath"
    expect "the daemon and its agents keep the umask they inherited" printed "UMASK=0022"
    expect "without a password file no password is passed" printed "PASEO_PASSWORD=unset"
    expect "the web UI is off by default" printed "PASEO_WEB_UI_ENABLED=false"
    expect "without hostnames none is passed" printed "PASEO_HOSTNAMES=unset"

    # b. A config.json the daemon wrote, with the plugin on.
    home=$work/b
    mkdir -p "$home/.paseo"
    printf '%s\n' '{"daemon": {"passwordHash": "example"}, "plugins": {"other": {"source": "directory", "path": "/var/empty/other", "enabled": false}}}' \
      > "$home/.paseo/config.json"
    run "$home" "$serve"
    expect "with an existing config.json the daemon starts" exited 0
    expect "an existing config.json keeps its daemon object" config '.daemon == {passwordHash: "example"}'
    expect "an existing config.json keeps another plugin's entry" \
      config '.plugins.other == {source: "directory", path: "/var/empty/other", enabled: false}'
    expect "an existing config.json gains the plugin entry and turns plugins on" \
      config --arg p "$plugin" '.pluginsEnabled == true and .plugins["paseo-direnv"] == {source: "directory", path: $p, enabled: true}'
    expect "the rewritten config.json is at mode 600" mode "$home/.paseo/config.json" 600
    expect "no temporary file is left after a rewrite" noTemporary
    inode=$(stat -c %i "$home/.paseo/config.json")
    run "$home" "$serve"
    expect "a config.json that already holds the entry is not rewritten" test "$(stat -c %i "$home/.paseo/config.json")" = "$inode"

    # c. A config.json with a stale plugin entry, with the plugin off.
    home=$work/c
    mkdir -p "$home/.paseo"
    printf '%s\n' '{"daemon": {"passwordHash": "example"}, "pluginsEnabled": true, "plugins": {"paseo-direnv": {"source": "directory", "path": "${builtins.storeDir}/00000000000000000000000000000000-paseo-direnv-0.1.0", "enabled": true}, "other": {"source": "directory", "path": "/var/empty/other", "enabled": false}}}' \
      > "$home/.paseo/config.json"
    run "$home" "$serveOff"
    expect "with the plugin off the daemon starts" exited 0
    expect "with the plugin off its entry is removed" config '.plugins | has("paseo-direnv") | not'
    expect "with the plugin off the other keys stay" \
      config '.daemon == {passwordHash: "example"} and .pluginsEnabled == true and .plugins.other == {source: "directory", path: "/var/empty/other", enabled: false}'
    expect "with the plugin off nothing sets worktree trust" printed "PASEO_DIRENV_TRUST_WORKTREES=unset"
    expect "with the plugin off direnv is not on the daemon's PATH" pathLacks '-direnv-[0-9.]*/bin$'
    expect "with the plugin off the daemon's PATH still starts with the codex launcher" pathStarts "$launcher"
    expect "with the plugin off no temporary file is left" noTemporary

    # d. No config.json, with the plugin off.
    home=$work/d
    mkdir -p "$home"
    run "$home" "$serveOff"
    expect "with the plugin off and no config.json the daemon starts" exited 0
    expect "with the plugin off a missing config.json is not created" missing "$home/.paseo/config.json"
    expect "with the plugin off no temporary file is created" noTemporary

    # e. A config.json jq cannot read, with the plugin on.
    home=$work/e
    mkdir -p "$home/.paseo"
    printf 'not json {\n' > "$home/.paseo/config.json"
    cp "$home/.paseo/config.json" "$work/e.orig"
    run "$home" "$serve"
    expect "a config.json jq cannot read stops the script" failed
    expect "the script names the file it cannot update" complained "cannot update"
    expect "the unreadable config.json is left byte for byte" cmp -s "$work/e.orig" "$home/.paseo/config.json"
    expect "paseo-server does not run beside an unreadable config.json" notStarted
    expect "no temporary file is left beside an unreadable config.json" noTemporary

    # f. The same file, with the plugin off.
    home=$work/f
    mkdir -p "$home/.paseo"
    printf 'not json {\n' > "$home/.paseo/config.json"
    cp "$home/.paseo/config.json" "$work/f.orig"
    run "$home" "$serveOff"
    expect "with the plugin off an unreadable config.json stops the script" failed
    expect "with the plugin off the script names the file it cannot update" complained "cannot update"
    expect "with the plugin off the unreadable config.json is left byte for byte" cmp -s "$work/f.orig" "$home/.paseo/config.json"
    expect "with the plugin off paseo-server does not run beside an unreadable config.json" notStarted

    # g. An empty config.json, with the plugin on and off.
    for script in "$serve" "$serveOff"; do
      home=$work/g
      rm -f "$home/.paseo/config.json"
      mkdir -p "$home/.paseo"
      : > "$home/.paseo/config.json"
      run "$home" "$script"
      expect "an empty config.json stops the script" failed
      expect "an empty config.json is named" complained "cannot update"
      expect "an empty config.json is left empty" test ! -s "$home/.paseo/config.json"
      expect "paseo-server does not run beside an empty config.json" notStarted
    done

    # h. The script Home Manager runs at each switch with the plugin off
    # removes a stale entry and leaves a file without one alone.
    home=$work/h
    mkdir -p "$home/.paseo"
    printf '%s\n' '{"daemon": {"passwordHash": "example"}, "plugins": {"paseo-direnv": {"source": "directory", "path": "${builtins.storeDir}/00000000000000000000000000000000-paseo-direnv-0.1.0", "enabled": true}}}' \
      > "$home/.paseo/config.json"
    run "$home" "$configOff"
    expect "the switch script exits 0" exited 0
    expect "the switch script removes the stale entry" config '.plugins | has("paseo-direnv") | not'
    expect "the switch script keeps the other keys" config '.daemon == {passwordHash: "example"}'
    inode=$(stat -c %i "$home/.paseo/config.json")
    run "$home" "$configOff"
    expect "the switch script leaves a config.json without the entry alone" test "$(stat -c %i "$home/.paseo/config.json")" = "$inode"

    # h2. An entry the user pointed at a checkout of their own stays with the
    # plugin off, at a start and at a switch.
    home=$work/own
    mkdir -p "$home/.paseo"
    printf '%s\n' '{"plugins": {"paseo-direnv": {"source": "directory", "path": "/var/empty/own", "enabled": true}}}' \
      > "$home/.paseo/config.json"
    cp "$home/.paseo/config.json" "$work/own.orig"
    run "$home" "$serveOff"
    expect "with the plugin off a start keeps an entry outside the store" cmp -s "$work/own.orig" "$home/.paseo/config.json"
    run "$home" "$configOff"
    expect "with the plugin off a switch keeps an entry outside the store" cmp -s "$work/own.orig" "$home/.paseo/config.json"

    # i. A password file, readable and missing.
    home=$work/i
    mkdir -p "$home"
    run "$home" "$servePassword"
    expect "a readable password file is passed as PASEO_PASSWORD" printed "PASEO_PASSWORD=example"
    home=$work/j
    mkdir -p "$home"
    run "$home" "$serveNoPassword"
    expect "a missing password file stops the script" failed
    expect "a missing password file is named" complained "cannot read the password file"
    expect "paseo-server does not run without its password file" notStarted

    # k. A daemon behind a reverse proxy, with the web UI on and two names.
    home=$work/k
    mkdir -p "$home"
    run "$home" "$serveProxied"
    expect "webUi.enable turns the web UI on" printed "PASEO_WEB_UI_ENABLED=true"
    expect "hostnames reach the daemon comma separated" printed "PASEO_HOSTNAMES=paseo.example.com,code.example.com"

    # l. The default package carries the web UI the daemon serves.
    expect "the default paseo package holds the daemon web UI" \
      test -f ${defaultPackage}/lib/paseo/packages/server/dist/server/web-ui/index.html

    [ "$fail" = 0 ] || exit 1
    touch "$out"
  ''
