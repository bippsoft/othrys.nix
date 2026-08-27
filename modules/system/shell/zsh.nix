# modules/system/shell/zsh.nix
# Zsh with alias presets and completion caching
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  hmEnabled = config.othrys.system.users.homeManaged;
  cfg = config.othrys.system.shell.zsh;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # A toggleable group of related aliases. Consumers disable groups they
  # don't want rather than inheriting one fixed workflow.
  presetOpt = name:
    lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the ${name} alias preset.";
    };
in {
  options.othrys.system.shell.zsh = {
    enable = lib.mkEnableOption "Zsh shell with full configuration";
    persistCompdump = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to persist .zcompdump across reboots.";
    };

    aliasPresets = {
      nix = presetOpt "Nix workflow (rebuild, nix-search, nix-clean)";
      navigation = presetOpt "directory navigation (.., ..., ...)";
      modernUnix = presetOpt "modern-unix replacements (eza ls, bat cat, colored grep/diff)";
      editor = presetOpt "editor shortcuts (v/vim/vi -> defaultEditor)";
      git = presetOpt "git shorthand (g, gs, ga, gc, ...)";
      python = presetOpt "python/uv shorthand (py, pip, venv)";
      jvm = presetOpt "maven/gradle shorthand";
      ansible = presetOpt "ansible shorthand (ap, al, av)";
      opentofu = presetOpt "opentofu shorthand (tf, tfi, tfp, ...)";
      node = presetOpt "npm/yarn/pnpm shorthand";
      docker = presetOpt "docker shorthand (d, dc, dps, ...)";
      # Unlike the other presets this defaults to desktop-only, since the aliases
      # target wl-copy/wl-paste, which need a Wayland session (and aren't
      # installed on headless hosts).
      clipboard =
        presetOpt "wayland clipboard (pbcopy/pbpaste -> wl-copy/wl-paste)"
        // {
          default = config.othrys.desktop.graphical;
          defaultText = lib.literalExpression "config.othrys.desktop.graphical";
        };
    };

    extraAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional shell aliases merged over the presets.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username} = {
        directories = [
          ".local/share/zoxide"
          ".local/share/direnv"
        ];
        files =
          [".zsh_history"]
          ++ lib.optionals cfg.persistCompdump [".zcompdump"];
      };
    };

    programs.zsh.enable = true;

    # Per-user shell config only when othrys manages the user account, guarded
    # at the attrset level so headless hosts never materialize a home-manager
    # user (see modules/system/nix.nix).
    home-manager.users = lib.mkIf hmEnabled {
      ${username} = {
        programs.zsh = {
          enable = true;
          enableCompletion = true;

          completionInit = ''
            autoload -Uz compinit
            if [[ -n ''${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
              compinit
            else
              compinit -C
            fi
          '';

          autosuggestion = {
            enable = true;
            strategy = ["history" "completion"];
          };

          syntaxHighlighting.enable = true;

          history = {
            size = 50000;
            save = 50000;
            path = "$HOME/.zsh_history";
            ignoreAllDups = true;
            ignoreSpace = true;
            share = true;
            extended = true;
          };

          historySubstringSearch.enable = true;

          shellAliases = let
            p = cfg.aliasPresets;
            editor = config.othrys.system.defaultEditor;
          in
            lib.optionalAttrs p.nix {
              rebuild = "sudo nixos-rebuild switch --flake .";
              rebuild-test = "sudo nixos-rebuild test --flake .";
              hm-switch = "home-manager switch --flake .";
              nix-search = "nix search nixpkgs";
              nix-clean = "sudo nix-collect-garbage -d && nix-collect-garbage -d";
            }
            // lib.optionalAttrs p.navigation {
              ".." = "cd ..";
              "..." = "cd ../..";
              "...." = "cd ../../..";
              "....." = "cd ../../../..";
            }
            // lib.optionalAttrs p.modernUnix {
              ls = "eza --icons --group-directories-first";
              ll = "eza -la --icons --group-directories-first";
              la = "eza -la --icons --group-directories-first";
              lt = "eza --tree --level=2 --icons";
              tree = "eza --tree --icons";
              cat = "bat";
              grep = "grep --color=auto";
              diff = "diff --color=auto";
            }
            // lib.optionalAttrs p.editor {
              v = editor;
              vim = editor;
              vi = editor;
            }
            // lib.optionalAttrs p.git {
              g = "git";
              gs = "git status";
              ga = "git add";
              gc = "git commit";
              gp = "git push";
              gl = "git pull";
              gd = "git diff";
              gco = "git checkout";
              gb = "git branch";
              glog = "git log --oneline --graph --decorate";
            }
            // lib.optionalAttrs p.python {
              py = "python3";
              pip = "uv pip";
              venv = "uv venv";
              uvx = "uvx";
            }
            // lib.optionalAttrs p.jvm {
              mvn-clean = "mvn clean install";
              gradle-build = "gradle clean build";
            }
            // lib.optionalAttrs p.ansible {
              ap = "ansible-playbook";
              al = "ansible-lint";
              av = "ansible-vault";
            }
            // lib.optionalAttrs p.opentofu {
              tf = "tofu";
              tfi = "tofu init";
              tfp = "tofu plan";
              tfa = "tofu apply";
              tfd = "tofu destroy";
              tfv = "tofu validate";
              tff = "tofu fmt";
            }
            // lib.optionalAttrs p.node {
              np = "npm";
              nr = "npm run";
              ni = "npm install";
              nid = "npm install --save-dev";
              nt = "npm test";
              y = "yarn";
              pn = "pnpm";
            }
            // lib.optionalAttrs p.docker {
              d = "docker";
              dc = "docker-compose";
              dps = "docker ps";
              dpa = "docker ps -a";
              dim = "docker images";
            }
            // lib.optionalAttrs p.clipboard {
              pbcopy = "wl-copy";
              pbpaste = "wl-paste";
            }
            // cfg.extraAliases;

          initContent = ''
            setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT
            setopt ALWAYS_TO_END AUTO_MENU AUTO_LIST COMPLETE_IN_WORD MENU_COMPLETE
            setopt EXTENDED_GLOB GLOB_DOTS NO_CASE_GLOB
            setopt HIST_VERIFY INC_APPEND_HISTORY SHARE_HISTORY
            setopt NO_BEEP

            zstyle ':completion:*' menu select
            zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
            zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"

            export EDITOR="${config.othrys.system.defaultEditor}"
            export VISUAL="${config.othrys.system.defaultEditor}"

            bindkey -e
            bindkey '^A' beginning-of-line
            bindkey '^E' end-of-line
            bindkey '^D' delete-char
            bindkey '^W' backward-kill-word
            bindkey '^U' backward-kill-line
            bindkey '^K' kill-line
            bindkey '^[[A' history-substring-search-up
            bindkey '^[[B' history-substring-search-down
            bindkey '^R' fzf-history-widget
            bindkey '^P' up-line-or-history
            bindkey '^N' down-line-or-history
            bindkey '^F' autosuggest-accept
            bindkey '^[[C' forward-char
            bindkey '^[[Z' reverse-menu-complete
            bindkey '^L' clear-screen
          '';
        };

        programs.fzf = {
          enable = true;
          enableZshIntegration = true;
          defaultCommand = "fd --type f --hidden --follow --exclude .git";
          defaultOptions =
            [
              "--height 40%"
              "--layout=reverse"
              "--border"
              "--inline-info"
              "--preview 'bat --color=always --style=numbers --line-range=:500 {}'"
              "--bind 'ctrl-/:toggle-preview'"
            ]
            # Clipboard yank needs a Wayland session, and follows the alias preset.
            ++ lib.optional cfg.aliasPresets.clipboard "--bind 'ctrl-y:execute-silent(echo {} | wl-copy)'";
          fileWidget.options = ["--preview 'bat --color=always --style=numbers --line-range=:500 {}'"];
          changeDirWidget.options = ["--preview 'eza --tree --level=2 --color=always {}'"];
        };

        programs.eza = {
          enable = true;
          enableZshIntegration = true;
          git = true;
          icons = "auto";
        };

        programs.zoxide = {
          enable = true;
          enableZshIntegration = true;
        };

        programs.direnv = {
          enable = true;
          enableZshIntegration = true;
          nix-direnv.enable = true;
        };

        programs.pay-respects = {
          enable = true;
          enableZshIntegration = true;
        };

        programs.bat = {
          enable = true;
          config = {
            style = "numbers,changes,header";
            wrap = "auto";
            paging = "auto";
          };
          extraPackages = with pkgs.bat-extras; [batgrep batman];
        };

        programs.ripgrep.enable = true;
      };
    };
  };
}
