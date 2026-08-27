# modules/system/shell/bash.nix
# Minimal Bash configuration as a fallback shell
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  hmEnabled = config.othrys.system.users.homeManaged;
  cfg = config.othrys.system.shell.bash;
in {
  options.othrys.system.shell.bash = {
    enable = lib.mkEnableOption "Bash with safe defaults";
  };

  config = lib.mkIf cfg.enable {
    # Per-user shell config only when othrys manages the user account
    # (see modules/system/nix.nix for the guard rationale).
    home-manager.users = lib.mkIf hmEnabled {
      ${username}.programs.bash = {
        enable = true;
        enableCompletion = true;
        enableVteIntegration = true;

        # Safe shell options
        shellOptions = [
          "histappend" # Append to history, don't overwrite
          "checkwinsize" # Update LINES/COLUMNS after each command
          "globstar" # ** matches recursively
          "checkjobs" # Warn before exiting with background jobs
          "cdspell" # Autocorrect minor cd typos
          "dirspell" # Autocorrect minor directory typos in completion
          "cmdhist" # Save multi-line commands as single entry
          "nocaseglob" # Case-insensitive globbing
        ];

        # History
        historySize = 50000;
        historyFileSize = 50000;
        historyFile = "$HOME/.bash_history";
        historyControl = [
          "ignoredups"
          "ignorespace"
          "erasedups"
        ];
        historyIgnore = [
          "ls"
          "cd"
          "exit"
          "clear"
        ];

        # Prompt is handled by starship (enableBashIntegration).
        initExtra = ''
          export EDITOR="${config.othrys.system.defaultEditor}"
          export VISUAL="${config.othrys.system.defaultEditor}"
        '';
      };
    };
  };
}
