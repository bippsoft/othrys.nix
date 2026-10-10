# modules/services/notify.nix
# Host notification dispatch, the implementation-agnostic client half of
# the notification pair (othrys.services.ntfy is the self-hosted server it
# points at by default, and any ntfy endpoint works).
#
# Provides:
# - `othrys-notify <title> [message...]` on PATH
# - a `notify-failure@.service` template unit, and modules attach
#   `onFailure = ["notify-failure@%n.service"]` (conditionally on this
#   module being enabled) so failing backups, health checks, and upgrades
#   reach a phone instead of dying silently in the journal.
{
  config,
  lib,
  pkgs,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  inherit (import ../lib/net.nix {inherit lib;}) local;
  sandbox = import ../lib/sandbox.nix;
  cfg = config.othrys.services.notify;
  ntfyCfg = config.othrys.services.ntfy;

  # A plain-HTTP URL whose host is this machine. The token is sent as a
  # bearer header, so over any other http:// URL it crosses the network in
  # clear, and the warning below says so.
  loopbackUrl = url: builtins.match "http://(127\\.[0-9.]+|localhost|[[]::1[]])(:[0-9]+)?(/.*)?" url != null;

  # The token never becomes a curl argument. An `-H "Authorization: Bearer $t"`
  # argv is world-readable through /proc/<pid>/cmdline for the life of the
  # request, which is the same rule the cachix-push wrapper follows in
  # modules/system/nix.nix. curl reads the header from a file instead, written
  # under umask 077 and removed on exit.
  #
  # Two callers read the token. A human running othrys-notify reads tokenFile
  # directly, and notify-failure@ runs under DynamicUser with no access to it,
  # so systemd stages it at $CREDENTIALS_DIRECTORY/token instead. When neither
  # is readable the script stops and names the file. A token was configured,
  # so a request without it would be refused by a topic that requires one and
  # would silently reach a topic that does not, and neither is what the
  # operator asked for.
  #
  # Every external tool is called by store path. The unit runs with no PATH
  # worth relying on, and an interactive caller's PATH is not this script's
  # concern either.
  notifyScript = pkgs.writeShellScriptBin "othrys-notify" ''
    set -eu
    title="''${1:?usage: othrys-notify <title> [message...]}"
    shift
    message="''${*:-$title}"

    auth=()
    ${lib.optionalString (cfg.tokenFile != null) ''
      token_file=${lib.escapeShellArg cfg.tokenFile}
      if [ -n "''${CREDENTIALS_DIRECTORY:-}" ] && [ -r "$CREDENTIALS_DIRECTORY/token" ]; then
        tokensrc="$CREDENTIALS_DIRECTORY/token"
      elif [ -r "$token_file" ]; then
        tokensrc="$token_file"
      else
        echo "othrys-notify: token file $token_file is missing or unreadable, refusing to send without it" >&2
        exit 1
      fi

      umask 077
      # An interactive run lands on the per-user tmpfs. The unit has no
      # XDG_RUNTIME_DIR and falls back to its private /tmp.
      hdrfile="$(${pkgs.coreutils}/bin/mktemp -p "''${XDG_RUNTIME_DIR:-/tmp}")"
      trap '${pkgs.coreutils}/bin/rm -f "$hdrfile"' EXIT
      printf 'Authorization: Bearer %s\n' "$(${pkgs.coreutils}/bin/cat "$tokensrc")" > "$hdrfile"
      auth=(-H "@$hdrfile")
    ''}

    ${pkgs.curl}/bin/curl -fsS -m 10 \
      -H "Title: $title" \
      "''${auth[@]}" \
      -d "$message" \
      "${cfg.url}/${cfg.topic}" > /dev/null
  '';
in {
  # ANCHOR: notify-options
  options.othrys.services.notify = {
    enable = lib.mkEnableOption "host notification dispatch (othrys-notify + systemd failure hooks)";

    url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      # The local server is reached at its listener as seen from this host
      # (modules/lib/net.nix), so an ntfy moved to one interface still works.
      default =
        if ntfyCfg.enable
        then "http://${local ntfyCfg.listenAddress}:${toString ntfyCfg.port}"
        else null;
      defaultText = lib.literalExpression "the local othrys.services.ntfy instance when enabled, else null";
      example = "https://ntfy.example.com";
      description = "ntfy endpoint notifications are published to. Follows the local ntfy server by default; point it at a fleet-central instance otherwise.";
    };

    topic = lib.mkOption {
      type = lib.types.str;
      default = "alerts";
      description = "ntfy topic notifications are published to (on public instances the topic is effectively a password, so use tokenFile or a private server).";
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      example = lib.literalExpression ''config.sops.secrets."notify/token".path'';
      description = "Path to a runtime file holding an ntfy access token (a secrets-provider path). Null sends unauthenticated.";
    };
  };
  # ANCHOR_END: notify-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.url != null;
        message = "othrys.services.notify: set url (or enable othrys.services.ntfy for a local server).";
      }
    ];

    warnings = lib.optional (cfg.tokenFile != null && cfg.url != null && lib.hasPrefix "http://" cfg.url && !loopbackUrl cfg.url) "othrys.services.notify: url is ${cfg.url} and tokenFile is set, so the token is sent in clear over the network on every notification. Use an https:// URL, or an ntfy on this host.";

    environment.systemPackages = [notifyScript];

    # The unit posts one HTTP request, so it needs network access, the token,
    # and nothing else. It ran as root with the full capability set, which is a
    # standing root process on every host that enables failure notifications.
    # DynamicUser plus LoadCredential gives it the token without giving it the
    # rest of /run/secrets.
    systemd.services."notify-failure@" = {
      description = "Failure notification for %i.";
      serviceConfig =
        {
          Type = "oneshot";
          ExecStart = "${notifyScript}/bin/othrys-notify \"%i failed on ${config.networking.hostName}\" \"systemd unit %i entered failed state on ${config.networking.hostName}\"";

          DynamicUser = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
        }
        // sandbox.baseline
        // lib.optionalAttrs (cfg.tokenFile != null) {
          LoadCredential = ["token:${cfg.tokenFile}"];
        };
    };
  };
}
