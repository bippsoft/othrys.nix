# modules/apps/gui/vscode/default.nix
# VS Code / VSCodium, wired to the shared language toolchains
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.vscode;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  nixvimPackage = config.home-manager.users.${username}.programs.nixvim.build.package;
in {
  options.othrys.apps.vscode = {
    enable = lib.mkEnableOption "VSCodium editor";

    extraExtensions = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional extensions to install.";
    };

    userSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Additional user settings to merge.";
    };

    neovimIntegration.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.othrys.apps.nixvim.enable;
      defaultText = lib.literalExpression "config.othrys.apps.nixvim.enable";
      description = ''
        Embed neovim as the editor core via vscode-neovim, using nixvim's
        neovim package. Follows nixvim by default; disable for a standalone
        VSCodium (vscode no longer hard-requires nixvim).
      '';
    };
  };

  # The assertion lives in its own mkIf because with neovim integration on the body
  # dereferences nixvim's HM package, so it must stay unevaluated when nixvim
  # is off or the raw "attribute 'nixvim' missing" error preempts the
  # assertion message during assertion collection.
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !cfg.neovimIntegration.enable || config.othrys.apps.nixvim.enable;
          message = "othrys.apps.vscode: neovimIntegration.enable requires othrys.apps.nixvim.enable = true (vscode-neovim embeds nixvim's neovim package). Enable nixvim or set othrys.apps.vscode.neovimIntegration.enable = false for standalone VSCodium.";
        }
      ];
    })
    (lib.mkIf (cfg.enable && (!cfg.neovimIntegration.enable || config.othrys.apps.nixvim.enable)) {
      environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
        users.${username}.directories = [
          ".config/VSCodium"
          ".vscode-oss"
        ];
      };

      home-manager.users.${username} = {
        imports = [
          # Language-specific extensions
          ./languages
        ];

        programs.vscodium = {
          enable = true;

          profiles.default = {
            enableUpdateCheck = false;
            enableExtensionUpdateCheck = false;

            extensions =
              (with pkgs.vscode-extensions; [
                mkhl.direnv
                editorconfig.editorconfig
                pkief.material-icon-theme
              ])
              ++ lib.optional cfg.neovimIntegration.enable pkgs.vscode-extensions.asvetliakov.vscode-neovim
              ++ cfg.extraExtensions;

            userSettings =
              {
                # Editor (fonts/colors handled by Stylix)
                "editor.formatOnSave" = true;
                "editor.tabSize" = 2;
                "editor.minimap.enabled" = false;
                "editor.bracketPairColorization.enabled" = true;

                "workbench.iconTheme" = "material-icon-theme";
                "window.titleBarStyle" = "custom";

                "telemetry.telemetryLevel" = "off";
              }
              # Neovim-core wiring only when the integration is on (the
              # nixvimPackage dereference stays lazy otherwise).
              // lib.optionalAttrs cfg.neovimIntegration.enable {
                "vscode-neovim.neovimExecutablePaths.linux" = "${nixvimPackage}/bin/nvim";
                "extensions.experimental.affinity" = {
                  "asvetliakov.vscode-neovim" = 1;
                };
              }
              // cfg.userSettings;
          };
        };
      };
    })
  ];
}
