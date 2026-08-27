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
  cfg = config.othrys.services.notify;
  ntfyCfg = config.othrys.services.ntfy;

  # The token never becomes a curl argument. An `-H "Authorization: Bearer $t"`
  # argv is world-readable through /proc/<pid>/cmdline for the life of the
  # request, which is the same rule the cachix-push wrapper follows in
  # modules/system/nix.nix. curl reads the header from a file instead, written
  # under umask 077 and removed on exit.
  #
  # Two callers read the token. A human running othrys-notify reads tokenFile
  # directly, and notify-failure@ runs under DynamicUser with no access to it,
  # so systemd stages it at $CREDENTIALS_DIRECTORY/token instead.
  notifyScript = pkgs.writeShellScriptBin "othrys-notify" ''
    set -eu
    title="''${1:?usage: othrys-notify <title> [message...]}"
    shift
    message="''${*:-$title}"

    auth=()
    ${lib.optionalString (cfg.tokenFile != null) ''
      tokensrc=""
      if [ -n "''${CREDENTIALS_DIRECTORY:-}" ] && [ -r "$CREDENTIALS_DIRECTORY/token" ]; then
        tokensrc="$CREDENTIALS_DIRECTORY/token"
      elif [ -r ${lib.escapeShellArg cfg.tokenFile} ]; then
        tokensrc=${lib.escapeShellArg cfg.tokenFile}
      fi

      if [ -n "$tokensrc" ]; then
        umask 077
        hdrfile="$(${pkgs.coreutils}/bin/mktemp)"
        trap 'rm -f "$hdrfile"' EXIT
        printf 'Authorization: Bearer %s\n' "$(cat "$tokensrc")" > "$hdrfile"
        auth=(-H "@$hdrfile")
      fi
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
      default =
        if ntfyCfg.enable
        then "http://127.0.0.1:${toString ntfyCfg.port}"
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
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];
          CapabilityBoundingSet = [""];
          AmbientCapabilities = [""];
          NoNewPrivileges = true;
        }
        // lib.optionalAttrs (cfg.tokenFile != null) {
          LoadCredential = ["token:${cfg.tokenFile}"];
        };
    };
  };
}
