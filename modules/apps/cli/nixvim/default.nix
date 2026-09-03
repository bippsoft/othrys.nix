# modules/apps/cli/nixvim/default.nix
# NixVim - Neovim configured via Nix
{
  config,
  lib,
  inputs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.nixvim;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # A toggleable plugin group. Consumers disable groups they don't want
  # rather than inheriting one fixed editor (the zsh aliasPresets pattern).
  presetOpt = name:
    lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the ${name} preset.";
    };
in {
  # presets.telescope became presets.picker when the fuzzy finder moved from
  # telescope to snacks.picker. The name described the plugin, not the job.
  imports = [
    (lib.mkRenamedOptionModule
      ["othrys" "apps" "nixvim" "presets" "telescope"]
      ["othrys" "apps" "nixvim" "presets" "picker"])
  ];

  options.othrys.apps.nixvim = {
    enable = lib.mkEnableOption "NixVim editor";

    # The LSP/completion/treesitter/formatting core is always on, since it is the
    # editor's essence. These groups are workflow choices, so they toggle.
    presets = {
      picker = presetOpt "snacks.picker fuzzy finding (<leader>f*)";
      git = presetOpt "gitsigns change indicators";
      diagnostics = presetOpt "Trouble diagnostics UI + todo-comments (<leader>x*)";
      fileTree = presetOpt "snacks.explorer file tree (<leader>e)";
      sessions = presetOpt "persistence.nvim session management (<leader>q*)";
      dashboard = presetOpt "snacks.dashboard start screen";
      statusline = presetOpt "lualine statusline";
      notifications = presetOpt "nvim-notify + dressing UI polish";
    };

    dashboard.subHeader = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Text lines shown under the start-screen logo (e.g. a personalized ASCII wordmark). Empty omits the block.";
    };

    extraPlugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      example = lib.literalExpression "[pkgs.vimPlugins.vim-sleuth]";
      description = "Additional vim plugins appended to the curated set.";
    };

    extraConfigLua = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional Lua configuration appended after the curated config.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Persistence for Neovim data (undo history, shada, etc.)
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".local/share/nvim"
      ];
    };

    othrys.internal.homeConfig."apps.nixvim" = {
      imports = [
        inputs.nixvim.homeModules.nixvim

        # Core configuration
        ./globals.nix
        ./options.nix
        ./autocmds.nix
        ./extraPackages.nix

        # Plugin modules
        ./plugins

        # Language modules
        ./languages
      ];

      programs.nixvim = {
        enable = true;

        # nixvim pins its own nixpkgs, but flake.nix makes it follow ours so
        # the fleet builds against one nixpkgs. Upstream warns when a follows
        # overrides that default, so state the choice explicitly to silence it.
        nixpkgs.source = inputs.nixpkgs;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
        vimdiffAlias = true;

        # Manpages and :h nixvim for the generated config. The JSON parsing
        # failure in nixvim's options.json that once forced this off is gone,
        # and restoring it costs 0.5 MiB on a 1.47 GiB closure.
        enableMan = true;

        # Consumer passthroughs
        inherit (cfg) extraPlugins;
        extraConfigLua = lib.mkIf (cfg.extraConfigLua != "") cfg.extraConfigLua;
      };
    };
  };
}
