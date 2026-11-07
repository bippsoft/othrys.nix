# modules/system/shell/zsh.nix
# Zsh with alias presets and completion caching
{
  config,
  lib,
  ...
}: let
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
}
