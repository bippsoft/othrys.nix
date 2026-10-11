# modules/apps/cli/ai/mcp/default.nix
# Base MCP configuration, enabling upstream programs.mcp and shared context
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.apps.ai.mcp;

  # Shared environment context for AI assistants. The root wipe is a
  # property of the host, so the line about it is rendered from the host's
  # impermanence setting rather than told to every host. It is appended to
  # the store bullet, the last of the "cannot do" list, and eval-claude-code
  # reads the rendered text back so an edit to that bullet is noticed.
  storeBullet = "- **No modifying /nix/store**: It's read-only and immutable\n";
  impermanenceBullet =
    lib.optionalString config.othrys.system.impermanence.enable
    "- **No persistent writes outside $HOME**: the root filesystem is wiped on every boot, and only paths the host declares as persistent survive it\n";
  # The data bullet is rendered the same way. Only a host that wipes its root
  # has to keep data in the home directory, so the reason is added there and
  # every other host reads the plain suggestion.
  dataBullet = "- **Store data**: In `$HOME` (~/.config, ~/.local, project directories)\n";
  impermanenceDataBullet = "- **Store data**: Only in `$HOME` (~/.config, ~/.local, project directories), since anything written elsewhere is gone after a reboot\n";
  globalContext =
    lib.replaceStrings
    [storeBullet dataBullet]
    [
      (storeBullet + impermanenceBullet)
      (
        if config.othrys.system.impermanence.enable
        then impermanenceDataBullet
        else dataBullet
      )
    ]
    (builtins.readFile ./nixos-context.md);

  # Check if any MCP server sub-module is enabled
  anyMcpEnabled = cfg.nixos.enable || cfg.context7.enable;
in {
  imports = [
    ./nixos.nix
    ./context7.nix
    (lib.mkRemovedOptionModule ["othrys" "apps" "ai" "mcp" "github"] "The GitHub MCP server kept a personal access token in the host's secrets. The gh CLI does the same work with the user's own login, so enable othrys.apps.gh and run `gh auth login`. With Claude Code on, othrys.apps.gh pre-approves the read-only gh commands.")
  ];

  options.othrys.apps.ai.mcp = {
    # Individual server configs are defined in their own modules
    # They register themselves under home-manager's programs.mcp.servers.<name>

    context = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = globalContext;
      defaultText = lib.literalMD "the text of `nixos-context.md` beside this module, with a line about the root wipe added when `othrys.system.impermanence.enable` is set";
      description = "Shared global context for AI assistants.";
    };
  };

  config = lib.mkIf anyMcpEnabled {
    othrys.internal.homeConfig."apps.ai.mcp".programs.mcp.enable = true;
  };
}
