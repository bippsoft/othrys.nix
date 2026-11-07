# modules/apps/gui/ghostty.nixos.nix
# The NixOS implementation of othrys.apps.ghostty
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.apps.ghostty;
in {
  imports = [./ghostty.nix];

  config = lib.mkIf cfg.enable {
    othrys.internal.homeConfig."apps.ghostty" = {
      programs.ghostty = {
        enable = true;

        # Shell integration toggles
        enableZshIntegration = cfg.shellIntegration.zsh;
        enableBashIntegration = cfg.shellIntegration.bash;

        # Syntax highlighting
        installBatSyntax = cfg.batSyntax;
        installVimSyntax = cfg.vimSyntax;

        # Keybindings
        clearDefaultKeybinds = cfg.keybindings.clearDefaults;

        settings =
          {
            # Cursor
            cursor-style = cfg.cursor.style;
            cursor-style-blink = cfg.cursor.blink;

            # Window / GTK
            window-decoration = cfg.window.decoration;
            window-padding-x = cfg.window.padding.x;
            window-padding-y = cfg.window.padding.y;
            gtk-titlebar = cfg.window.gtkTitlebar;

            # Scrollback, in bytes
            scrollback-limit = cfg.scrollbackLimit;

            # Mouse
            mouse-hide-while-typing = cfg.mouseHideWhileTyping;
            copy-on-select = cfg.copyOnSelect;

            # Behaviour
            working-directory = "home";
            confirm-close-surface = false;
            gtk-single-instance = false;
          }
          // lib.optionalAttrs cfg.keybindings.enable {
            keybind =
              [
                "ctrl+shift+c=copy_to_clipboard"
                "ctrl+shift+v=paste_from_clipboard"
                "ctrl+shift+t=new_tab"
                "ctrl+shift+w=close_surface"
                "ctrl+shift+l=new_split:right"
                "ctrl+shift+j=new_split:down"
                "ctrl+shift+h=new_split:left"
                "ctrl+shift+k=new_split:up"
                "alt+l=goto_split:right"
                "alt+j=goto_split:down"
                "alt+h=goto_split:left"
                "alt+k=goto_split:up"
                "ctrl+shift+equal=increase_font_size:1"
                "ctrl+shift+minus=decrease_font_size:1"
                "ctrl+shift+0=reset_font_size"
              ]
              ++ cfg.keybindings.extra;
          }
          // cfg.extraSettings;
      };
    };
  };
}
