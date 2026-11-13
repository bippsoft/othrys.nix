# modules/apps/cli/ai/paseo.darwin.nix
# The nix-darwin implementation of othrys.apps.ai.paseo
#
# The daemon is the user's launchd agent, which launchd starts at the user's
# login and again whenever it exits, so it runs while the user is logged in.
# othrys controls no firewall on macOS, so under `"lan"` every peer that
# reaches the Mac reaches the port, and `"tailscale"` binds the tailnet
# address alone.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.ai.paseo;
  user = config.othrys.system.user.name;
  service = cfg.enable && cfg.service.enable;
  inherit (config.othrys.internal.paseo) serve;
in {
  imports = [./paseo.nix];

  config = lib.mkIf service {
    # A function, for the home directory the logs go to.
    othrys.internal.homeConfig."apps.ai.paseo-service" = {config, ...}: {
      launchd.agents.paseo = {
        enable = true;
        config = {
          ProgramArguments = ["${serve}"];
          RunAtLoad = true;
          KeepAlive = true;
          # The tailnet address may be missing for a while after login, and
          # launchd starts the daemon again no sooner than this.
          ThrottleInterval = 10;
          # The agents run git and the user's own tools. git comes ahead of
          # /usr/bin, whose git is a stub on a Mac without the Command Line
          # Tools, and /usr/bin and /bin carry the shell and the system tools
          # macOS ships.
          EnvironmentVariables.PATH = "/etc/profiles/per-user/${user}/bin:/run/current-system/sw/bin:${pkgs.git}/bin:/usr/bin:/bin";
          # The daemon's log.
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/paseo.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/paseo.log";
        };
      };
    };
  };
}
