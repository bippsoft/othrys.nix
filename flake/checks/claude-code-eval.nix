# flake/checks/claude-code-eval.nix
# CORE. What the AI modules hand Claude Code, read back from the rendered
# Home Manager settings of an evaluated host. The pre-approved MCP tool
# names once carried a plugin name Home Manager does not use, so none of
# them matched and every call prompted, and the github server's secret was
# owned by root while the wrapper that reads it runs as the user. The
# allow-list once carried a bare `Edit`, which approved every edit while the
# docs said edits are prompted, and a format hook that read a variable
# Claude Code never sets. None of it fails evaluation.
{
  hostConfig,
  mkExpectations,
  functioningHost,
  bootBase,
  inputs,
}: let
  aiModules = {
    othrys.apps.ai = {
      claude-code.enable = true;
      mcp = {
        nixos.enable = true;
        context7.enable = true;
      };
    };
  };
  # The shared context is rendered from the host's impermanence setting, so
  # it is read from a host with the root wipe on and from one without.
  impermanenceHost = hostConfig [
    bootBase
    aiModules
    {
      disko.enableConfig = false;
      fileSystems = {
        "/nix" = {
          device = "/dev/disk/by-label/nix";
          fsType = "btrfs";
        };
        "/persist" = {
          device = "/dev/disk/by-label/persist";
          fsType = "btrfs";
        };
      };
      othrys.system = {
        disko = {
          enable = true;
          device = "/dev/disk/by-id/example";
        };
        impermanence.enable = true;
      };
    }
  ];
  mentionsWipe = h: inputs.nixpkgs.lib.hasInfix "wiped on every boot" h.othrys.apps.ai.mcp.context;
  host = hostConfig [
    functioningHost
    {
      othrys.system.nix.allowUnfree = true;
      othrys.system.secrets.enable = true;
      # Not a real sops file. The check reads ownership and tool names, not
      # a decryption.
      othrys.apps.ai.mcp.github.secret.sopsFile = ./claude-code-eval.nix;
      sops.validateSopsFiles = false;
      othrys.apps.ai = {
        claude-code.enable = true;
        mcp = {
          nixos.enable = true;
          context7.enable = true;
          github.enable = true;
        };
      };
    }
  ];
  user = host.othrys.system.user.name;
  hm = host.home-manager.users.${user};
  settings = hm.programs.claude-code.settings;
  inherit (settings.permissions) allow;
  # A rule is a tool name followed by a parenthesised specifier, or the full
  # name of one MCP tool. A bare built-in tool name approves every call of
  # that tool.
  scoped = e: builtins.match "[A-Za-z]+[(].*[)]" e != null || builtins.match "mcp__.*" e != null;
  prefix = e: builtins.match "Bash[(](find|nix eval|nix fmt|just)[: )].*" e != null;
  mcpEntries = builtins.filter (e: builtins.match "mcp__.*" e != null) allow;
  # The plugin Home Manager synthesises from programs.mcp.servers is named
  # by a plain binding in its module, not an option, so the name this
  # repository uses is read from its one file and checked against upstream's
  # source as pinned in the lock. A rename upstream fails here first.
  inherit (import ../../modules/apps/cli/ai/mcp/plugin-name.nix) pluginName;
  upstreamModule = builtins.readFile "${inputs.home-manager}/modules/programs/claude-code/default.nix";
  upstreamNames = builtins.match ".*generatedPluginName = \"([^\"]+)\";.*" upstreamModule;
  pluginNames = [pluginName];
  servers = builtins.attrNames hm.programs.mcp.servers;
  parse = e: builtins.match "mcp__plugin_([^_]+)_([^_]+)__.*" e;
  entryOk = e: let
    m = parse e;
  in
    m != null && builtins.elem (builtins.elemAt m 0) pluginNames && builtins.elem (builtins.elemAt m 1) servers;
in
  mkExpectations "othrys-eval-claude-code" {
    "Home Manager still names its generated plugin as this repository does" = upstreamNames != null && builtins.head upstreamNames == pluginName;
    "every pre-approved MCP tool names the generated plugin and a declared server" = mcpEntries != [] && builtins.all entryOk mcpEntries;
    "no pre-approved tool carries the old plugin name" = !builtins.any (e: builtins.match ".*claude-code-home-manager.*" e != null) allow;
    "the context7 server carries no token header" = !(hm.programs.mcp.servers.context7.headers ? CONTEXT7_API_KEY);
    "the github secret is owned by the primary user" = host.sops.secrets.${host.othrys.apps.ai.mcp.github.secret.path}.owner == user;
    "every pre-approved rule names a tool and a specifier" = allow != [] && builtins.all scoped allow;
    "find, nix eval, nix fmt and just are not pre-approved" = !builtins.any prefix allow;
    "edits stay prompted" = settings.permissions.defaultMode == "default";
    "no hook is registered" = !(settings ? hooks);
    "the context names the root wipe on an impermanence host" = mentionsWipe impermanenceHost;
    "the context does not name the root wipe on a host with a persistent root" = !mentionsWipe host;
  }
