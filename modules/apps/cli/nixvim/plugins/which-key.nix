# modules/apps/cli/nixvim/plugins/which-key.nix
# Which-key: keybinding discoverability (always on, since it documents whatever
# the enabled presets install). Only GROUP labels are declared here, while the
# per-key descriptions come from each keymap's own `desc`, which which-key
# discovers automatically, so there is no duplicated registry to keep in sync.
_: {
  programs.nixvim = {
    plugins.which-key.enable = true;

    extraConfigLua = ''
      local wk_ok, wk = pcall(require, 'which-key')
      if wk_ok then
        wk.add({
          { "<leader>d", group = "Diagnostics" },
          { "<leader>f", group = "Format/Find" },
          { "<leader>c", group = "Code" },
          { "<leader>w", group = "Workspace" },
          { "<leader>x", group = "Trouble/Diagnostics" },
          { "<leader>q", group = "Session" },
          { "<leader>n", group = "Notifications" },
          { "<leader>b", group = "Buffer" },
        })
      end
    '';
  };
}
