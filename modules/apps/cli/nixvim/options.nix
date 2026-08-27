# modules/apps/cli/nixvim/options.nix
# Editor options (programs.nixvim.opts)
_: {
  programs.nixvim.opts = {
    # Line numbers
    number = true;
    relativenumber = true;

    # Mouse support
    mouse = "a";

    # Search settings
    ignorecase = true;
    smartcase = true;
    hlsearch = false;

    # Display settings
    # Wrap at the window edge, but break on word boundaries rather than
    # mid-word (linebreak), keep the wrapped continuation aligned with the
    # original indent (breakindent), and mark it so a wrapped line is never
    # mistaken for a new one.
    wrap = true;
    linebreak = true;
    breakindent = true;
    showbreak = "↪ ";
    termguicolors = true;
    cmdheight = 0; # Remove gap below statusline

    # Tab settings
    tabstop = 2;
    shiftwidth = 2;
    expandtab = true;

    # Diagnostic settings
    signcolumn = "yes";

    # Performance optimizations
    updatetime = 300;
    timeoutlen = 500;

    # Better completion experience
    completeopt = ["menu" "menuone" "noselect"];

    # Persistent undo
    undofile = true;
    undolevels = 10000;

    # Better search
    inccommand = "split";

    # Scroll offset
    scrolloff = 8;
    sidescrolloff = 8;

    # Column settings
    colorcolumn = "120";

    # Split behavior
    splitright = true;
    splitbelow = true;

    # Better diff
    diffopt = ["internal" "filler" "closeoff" "vertical"];

    # Fold settings
    foldmethod = "expr";
    foldexpr = "nvim_treesitter#foldexpr()";
    foldenable = false;
    foldlevel = 99;
  };

  # With wrap on, a bare j/k jumps a whole logical line and skips over the
  # visible rows of a wrapped paragraph. Move by display line instead, but only
  # when no count was given, so 5j still means five real lines and macros and
  # relative-number jumps keep working.
  programs.nixvim.keymaps = [
    {
      mode = ["n" "v"];
      key = "j";
      action = "v:count == 0 ? 'gj' : 'j'";
      options = {
        expr = true;
        silent = true;
        desc = "Down one display line";
      };
    }
    {
      mode = ["n" "v"];
      key = "k";
      action = "v:count == 0 ? 'gk' : 'k'";
      options = {
        expr = true;
        silent = true;
        desc = "Up one display line";
      };
    }
  ];
}
