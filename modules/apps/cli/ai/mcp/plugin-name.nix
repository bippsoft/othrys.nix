# modules/apps/cli/ai/mcp/plugin-name.nix
# The name Home Manager's programs.claude-code gives the plugin it synthesises
# from programs.mcp.servers, which is the middle part of every tool name
# (`mcp__plugin_<name>_<server>__<tool>`) a module pre-approves. Upstream keeps
# it as a let binding, `generatedPluginName`, in
# modules/programs/claude-code/default.nix rather than an option, so it is
# repeated here and read back by the eval-claude-code check against the
# rendered settings.
{
  pluginName = "hm";
}
