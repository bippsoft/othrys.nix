# modules/apps/gui/kitty.nix
# Kitty terminal emulator
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.apps.kitty;
in {
  options.othrys.apps.kitty = {
    enable = lib.mkEnableOption "Kitty terminal emulator";
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.homeConfig."apps.kitty" = {
      programs.kitty = {
        enable = true;

        settings = {
          # Font features
          disable_ligatures = "cursor";
          bold_font = "auto";
          italic_font = "auto";
          bold_italic_font = "auto";

          # Cursor
          cursor_shape = "block";
          cursor_blink_interval = "0.5";
          cursor_stop_blinking_after = "15.0";

          # Scrollback
          scrollback_lines = "10000";

          # Mouse
          mouse_hide_wait = "3.0";
          copy_on_select = "yes";

          # URL handling
          url_style = "curly";

          # Window layout
          window_padding_width = "8";
          hide_window_decorations = "no";
          window_resize_step_cells = "2";

          # Tabs
          tab_bar_edge = "bottom";
          tab_bar_style = "powerline";
          tab_powerline_style = "angled";

          # Bell
          visual_bell_duration = "0.0";
          enable_audio_bell = "no";

          # Performance
          repaint_delay = "10";
          input_delay = "3";
          sync_to_monitor = "yes";

          # Advanced
          editor = "nvim";
          confirm_os_window_close = "0";
          allow_remote_control = "yes";
        };

        shellIntegration = {
          enableBashIntegration = true;
          enableZshIntegration = true;
          enableFishIntegration = true;
        };
      };
    };
  };
}
