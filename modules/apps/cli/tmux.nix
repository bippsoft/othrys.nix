# modules/apps/cli/tmux.nix
# tmux terminal multiplexer, with a status line coloured from the theme palette
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.tmux;
  theme = config.othrys.theme;

  # A palette colour where the host has a palette, and otherwise the ANSI
  # name in the same position, as the starship prompt does.
  colour = base: ansi:
    if theme.palette != null
    then theme.colors.withHashtag.${base}
    else ansi;
in {
  # ANCHOR: tmux-options
  options.othrys.apps.tmux = {
    enable = lib.mkEnableOption "tmux terminal multiplexer";
  };
  # ANCHOR_END: tmux-options

  config = lib.mkIf cfg.enable {
    othrys.internal.homeConfig."apps.tmux" = {
      programs.tmux = {
        enable = true;
        # tmux-256color carries italics, which screen-256color lacks.
        terminal = lib.mkDefault "tmux-256color";
        # The default half-second delay after Escape stalls modal editors.
        escapeTime = lib.mkDefault 10;
        historyLimit = lib.mkDefault 50000;
        # The Stylix adapter turns its own tmux target off while this module
        # is on, so these lines are the only theme.
        extraConfig = ''
          set -g status-style "bg=${colour "base01" "default"},fg=${colour "base05" "default"}"
          set -g window-status-current-style "fg=${colour "base0D" "blue"},bold"
          set -g pane-active-border-style "fg=${colour "base0D" "blue"}"
          set -g message-style "bg=${colour "base02" "default"},fg=${colour "base05" "default"}"
        '';
      };

      # The terminfo database macOS ships has no tmux-256color entry, so
      # Apple's own programs inside tmux would not know the terminal.
      # nix-darwin puts each profile's share/terminfo on TERMINFO_DIRS.
      home.packages = lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.tmux.terminfo;
    };
  };
}
