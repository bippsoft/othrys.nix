# modules/apps/cli/ai/t3code.darwin.nix
# The nix-darwin implementation of othrys.apps.ai.t3code
#
# The headless server is the user's launchd agent, which launchd starts at
# the user's login and again whenever it exits, so it runs while the user is
# logged in. othrys controls no firewall on macOS, so `listen` alone decides
# who reaches the port, through the peer filter of `"lan"` or the tailnet
# address `"tailscale"` binds.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.ai.t3code;
  user = config.othrys.system.user.name;
  headless = cfg.enable && cfg.mode == "headless";
  inherit (config.othrys.internal.t3code) serve;
in {
  imports = [./t3code.nix];

  config = lib.mkIf headless {
    # A function, for the home directory the logs go to.
    othrys.internal.homeConfig."apps.ai.t3code-service" = {config, ...}: {
      launchd.agents.t3code = {
        enable = true;
        config = {
          ProgramArguments = ["${serve}"];
          RunAtLoad = true;
          KeepAlive = true;
          # The tailnet address may be missing for a while after login, and
          # launchd starts the server again no sooner than this.
          ThrottleInterval = 10;
          # The agents run git and the user's own tools. git comes ahead of
          # /usr/bin, whose git is a stub on a Mac without the Command Line
          # Tools, and /usr/bin and /bin carry the shell and the system tools
          # macOS ships.
          EnvironmentVariables.PATH = "/etc/profiles/per-user/${user}/bin:/run/current-system/sw/bin:${pkgs.git}/bin:/usr/bin:/bin";
          # The startup pairing link and the server's log.
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/t3code.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/t3code.log";
        };
      };
    };
  };
}
