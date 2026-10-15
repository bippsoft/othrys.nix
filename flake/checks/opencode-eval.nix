# flake/checks/opencode-eval.nix
# CORE. What the AI modules hand OpenCode, read back from the rendered Home
# Manager configuration of an evaluated host. OpenCode's own defaults allow
# every edit and every command, and it reads Claude Code's skill directory
# beside its own, so a shared skill written to both would be listed twice.
# The typed sharing option also refuses values outside its three modes.
{
  hostConfig,
  mkExpectations,
  functioningHost,
  inputs,
}: let
  inherit (inputs.nixpkgs) lib;
  skillText = name: "---\nname: ${name}\ndescription: ${name}\n---\n${name}\n";
  mk = extra:
    hostConfig [
      functioningHost
      {
        othrys.apps.ai = {
          opencode.enable = true;
          mcp.nixos.enable = true;
          skills.shared-skill = skillText "shared-skill";
          opencode.skills.opencode-only = skillText "opencode-only";
        };
      }
      extra
    ];
  hmOf = h: h.home-manager.users.${h.othrys.system.user.name};
  alone = mk {};
  hm = hmOf alone;
  inherit (hm.programs.opencode) settings;

  shareOf = value: (hmOf (mk {othrys.apps.ai.opencode.share = value;})).programs.opencode.settings.share;
  shareOverridden = hmOf (mk {
    othrys.apps.ai.opencode = {
      share = "auto";
      settings.share = "manual";
    };
  });
  # Force the scalar option because trying the host attrset alone would
  # leave its type check unevaluated.
  shareRejected = value: !(builtins.tryEval (mk {othrys.apps.ai.opencode.share = value;}).othrys.apps.ai.opencode.share).success;
  off = mk {othrys.apps.ai.opencode.enable = lib.mkForce false;};

  withClaude = hmOf (mk {
    othrys.system.nix.allowUnfree = true;
    othrys.apps.ai.claude-code.enable = true;
  });
  withClaudeApart = hmOf (mk {
    othrys.system.nix.allowUnfree = true;
    othrys.apps.ai = {
      claude-code.enable = true;
      opencode.claudeCompat = false;
    };
  });

  withOllama = hmOf (mk {
    othrys.apps.ai.ollama = {
      enable = true;
      acceleration = "cpu";
      loadModels = ["llama3.1"];
    };
  });
  withOllamaOff = hmOf (mk {
    othrys.apps.ai = {
      ollama = {
        enable = true;
        acceleration = "cpu";
      };
      opencode.ollama.enable = false;
    };
  });

  overridden = hmOf (mk {
    othrys.apps.ai.opencode = {
      permissions = {
        edit = "allow";
        extraBash."cargo test*" = "allow";
      };
      settings.permission.bash."git add*" = "ask";
    };
  });
in
  mkExpectations "othrys-eval-opencode" {
    "session sharing is disabled by default" = settings.share == "disabled";
    "explicit manual sharing reaches OpenCode" = shareOf "manual" == "manual";
    "explicit automatic sharing reaches OpenCode" = shareOf "auto" == "auto";
    "explicit disabled sharing reaches OpenCode" = shareOf "disabled" == "disabled";
    "settings.share overrides the typed sharing option" = shareOverridden.programs.opencode.settings.share == "manual";
    "an unknown sharing mode is refused" = shareRejected "bogus";
    "a boolean sharing mode is refused" = shareRejected true;
    "a null sharing mode is refused" = shareRejected null;
    "an integer sharing mode is refused" = shareRejected 1;
    "disabled OpenCode writes no sharing setting or registry entries" = !((hmOf off).programs.opencode.settings ? share) && !(off.othrys.internal.homeConfig ? "apps.ai.opencode") && !(off.othrys.internal.persist ? "apps.ai.opencode");
    "edits and commands are prompted" = settings.permission.edit == "ask" && settings.permission.bash."*" == "ask";
    "the read-only git commands run without a prompt" = settings.permission.bash."git diff*" == "allow" && settings.permission.bash."git status*" == "allow";
    "rm -rf and sudo are denied" = settings.permission.bash."rm -rf*" == "deny" && settings.permission.bash."sudo *" == "deny";
    "the catch-all is the first pattern written" = builtins.head (builtins.attrNames settings.permission.bash) == "*";
    "the tool does not update itself" = !settings.autoupdate;
    "the shared context is the global AGENTS.md" = hm.programs.opencode.context == alone.othrys.apps.ai.context.text && lib.hasInfix "/nix/store" hm.programs.opencode.context;
    "the declared MCP servers are handed over" = hm.programs.opencode.enableMcpIntegration && hm.programs.mcp.servers ? nixos;
    "a shared skill and a skill for the tool both reach OpenCode" = hm.programs.opencode.skills ? shared-skill && hm.programs.opencode.skills ? opencode-only;
    "beside Claude Code a shared skill is written once" = !(withClaude.programs.opencode.skills ? shared-skill) && withClaude.programs.claude-code.skills ? shared-skill && withClaude.programs.opencode.skills ? opencode-only;
    "Claude Code's files are read by default" = !(hm.home.sessionVariables ? OPENCODE_DISABLE_CLAUDE_CODE);
    "with the compatibility off the shared skill is written for both" = withClaudeApart.programs.opencode.skills ? shared-skill && withClaudeApart.home.sessionVariables.OPENCODE_DISABLE_CLAUDE_CODE == "1";
    "no Ollama provider without the server" = !(settings ? provider);
    "the Ollama provider names the local endpoint and the loaded models" = withOllama.programs.opencode.settings.provider.ollama.options.baseURL == "http://127.0.0.1:11434/v1" && withOllama.programs.opencode.settings.provider.ollama.models ? "llama3.1";
    "the Ollama provider can be left out" = !(withOllamaOff.programs.opencode.settings ? provider);
    "the host's permissions and settings win" = overridden.programs.opencode.settings.permission.edit == "allow" && overridden.programs.opencode.settings.permission.bash."cargo test*" == "allow" && overridden.programs.opencode.settings.permission.bash."git add*" == "ask";
    "the credentials directory is persisted at 0700" = builtins.any (d: (d.directory or d) == ".local/share/opencode" && (d.mode or "") == "0700") alone.othrys.internal.persist."apps.ai.opencode".user.directories;
  }
