# modules/apps/cli/nixvim/plugins/dashboard.nix
# Start screen via snacks.dashboard (presets.dashboard). Entries adapt to the
# other presets, so picker-backed items and session restore only appear when their
# preset provides the implementation.
{
  lib,
  osConfig,
  ...
}: let
  inherit (osConfig.othrys.apps.nixvim) presets;
  inherit (osConfig.othrys.apps.nixvim.dashboard) subHeader;

  # Dashboard palette, derived from the Stylix scheme when the host themes
  # itself, with a neutral NixOS-blue fallback so nixvim stays fully usable on
  # servers that never enable stylix (the branch keeps the stylix read lazy, so
  # there is no hard dependency).
  palette =
    if osConfig.othrys.system.stylix.enable
    then
      with osConfig.lib.stylix.colors.withHashtag; {
        primary = base0D;
        accent = base0C;
        emphasis = base05;
        muted = base03;
        faint = base02;
      }
    else {
      primary = "#5277C3"; # NixOS blue (darker shade)
      accent = "#7FB7FF"; # NixOS blue (lighter shade)
      emphasis = "#FFFFFF";
      muted = "#7C7C7C";
      faint = "#4A4A4A";
    };

  logo = [
    "       ◢██◣   ◥███◣  ◢██◣"
    "       ◥███◣   ◥███◣◢███◤"
    "        ◥███◣   ◥██████◤"
    "    ◢█████████████████◤   ◢◣"
    "   ◢██████████████████◣  ◢██◣"
    "        ◢███◤      ◥███◣◢███◤"
    "       ◢███◤        ◥██████◤"
    "◢█████████◤          ◥█████████◣"
    "◥█████████◣          ◢█████████◤"
    "    ◢██████◣        ◢███◤"
    "   ◢███◤◥███◣      ◢███◤"
    "   ◥██◤  ◥██████████████████◤"
    "    ◥◤   ◢█████████████████◤"
    "        ◢██████◣   ◥███◣"
    "       ◢███◤◥███◣   ◥███◣"
    "       ◥██◤  ◥███◣   ◥██◤"
  ];

  mkKey = k: icon: desc: action: {
    key = k;
    inherit icon desc action;
  };
in {
  config = lib.mkIf presets.dashboard {
    programs.nixvim = {
      plugins.snacks = {
        enable = true;

        settings.dashboard = {
          enabled = true;

          preset = {
            header = lib.concatStringsSep "\n" logo;

            # Only the entries whose preset backs them.
            keys =
              lib.optionals presets.picker [
                (mkKey "f" "  " "Find File" ":lua Snacks.picker.files()")
              ]
              ++ [
                (mkKey "n" "  " "New File" ":ene | startinsert")
              ]
              ++ lib.optionals presets.picker [
                (mkKey "r" "  " "Recent Files" ":lua Snacks.picker.recent()")
                (mkKey "g" "  " "Find Text" ":lua Snacks.picker.grep()")
              ]
              ++ lib.optionals presets.sessions [
                (mkKey "s" "  " "Restore Session" ":lua require('persistence').load()")
              ]
              ++ [
                (mkKey "q" "  " "Quit" ":qa")
              ];
          };

          sections =
            [{section = "header";}]
            ++ lib.optionals (subHeader != []) [
              {
                text = lib.concatStringsSep "\n" subHeader;
                hl = "SnacksDashboardSubHeader";
                align = "center";
                padding = 1;
              }
            ]
            ++ [
              {
                section = "keys";
                gap = 1;
                padding = 1;
              }
            ];
        };
      };

      # Palette injected from Nix (see the `palette` binding above), re-applied
      # on colorscheme changes so a light/dark flip does not strand the
      # dashboard on the previous scheme's contrast.
      #
      # Note the sections list above deliberately omits snacks' "startup"
      # section. It calls require("lazy.stats"), which exists only under
      # lazy.nvim, and plugins here come from the Nix store via packpath, so
      # including it aborts the UIEnter autocommand and the dashboard never
      # renders.
      extraConfigLua = ''
        local nix_colors = {
          dark_blue = "${palette.primary}",
          light_blue = "${palette.accent}",
          white = "${palette.emphasis}",
          gray = "${palette.muted}",
          dark_gray = "${palette.faint}",
        }

        local function apply_dashboard_colors()
          local dark = vim.o.background == "dark"
          local c = {
            header = dark and nix_colors.light_blue or nix_colors.dark_blue,
            subheader = dark and nix_colors.dark_blue or nix_colors.light_blue,
            desc = dark and nix_colors.white or nix_colors.dark_gray,
            key = dark and nix_colors.light_blue or nix_colors.dark_blue,
            footer = nix_colors.gray,
          }

          vim.api.nvim_set_hl(0, "SnacksDashboardHeader", { fg = c.header, bold = true })
          vim.api.nvim_set_hl(0, "SnacksDashboardSubHeader", { fg = c.subheader, bold = true })
          vim.api.nvim_set_hl(0, "SnacksDashboardDesc", { fg = c.desc })
          vim.api.nvim_set_hl(0, "SnacksDashboardIcon", { fg = c.key })
          vim.api.nvim_set_hl(0, "SnacksDashboardKey", { fg = c.key, bold = true })
          vim.api.nvim_set_hl(0, "SnacksDashboardFooter", { fg = c.footer, italic = true })
          vim.api.nvim_set_hl(0, "SnacksDashboardTitle", { fg = c.header, bold = true })
        end

        apply_dashboard_colors()

        vim.api.nvim_create_autocmd({ "ColorScheme", "OptionSet" }, {
          group = vim.api.nvim_create_augroup("othrys_dashboard_colors", { clear = true }),
          pattern = { "*", "background" },
          callback = apply_dashboard_colors,
          desc = "Re-apply dashboard palette on scheme change",
        })
      '';
    };
  };
}
