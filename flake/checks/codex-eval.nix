# flake/checks/codex-eval.nix
# CORE. What the codex module hands Codex, read back from the rendered Home
# Manager configuration of an evaluated host. The package, the telemetry
# switches and the sign-in store are settings nothing reads at evaluation, so
# a module that dropped one would still evaluate.
{
  hostConfig,
  mkExpectations,
  functioningHost,
  inputs,
  system,
}: let
  same = a: b: a.outPath == b.outPath;
  host = extra:
    hostConfig [
      functioningHost
      {
        othrys.apps.ai = {
          codex.enable = true;
          mcp.context7.enable = true;
          skills.shared-skill = "---\nname: shared-skill\ndescription: shared\n---\nshared\n";
          codex.skills.codex-only = "---\nname: codex-only\ndescription: own\n---\nown\n";
        };
      }
      extra
    ];
  hmOf = h: h.home-manager.users.${h.othrys.system.user.name};
  plain = host {};
  hm = hmOf plain;
  settings = hm.programs.codex.settings;
  telemetryOn = (hmOf (host {othrys.apps.ai.codex.disableTelemetry = false;})).programs.codex.settings;
  overridden = (hmOf (host {othrys.apps.ai.codex.settings.analytics.enabled = true;})).programs.codex.settings;
  swapped = hostConfig [
    functioningHost
    ({pkgs, ...}: {
      othrys.apps.ai.codex = {
        enable = true;
        package = pkgs.hello;
      };
    })
  ];
  off = hostConfig [functioningHost];
  llmCodex = inputs.llm-agents.packages.${system}.codex;
  installed = hm.programs.codex.package;
  # The same host with the project-environment launcher turned off.
  unwrapped = host {othrys.apps.ai.projectEnvironment.enable = false;};
  accepting = (hmOf (host {othrys.apps.ai.codex.permissions.mode = "acceptEdits";})).programs.codex.settings;
  withRule = (hmOf (host {othrys.apps.ai.codex.permissions.extraRules = ''prefix_rule(pattern = ["cargo", "test"], decision = "allow")'';})).programs.codex.rules.othrys;
  rules = hm.programs.codex.rules.othrys;
  profile = settings.permissions.othrys;
in
  mkExpectations "othrys-eval-codex" {
    "the package is the project-environment launcher around llm-agents' codex" = same installed.passthru.unwrapped llmCodex && !(same installed llmCodex);
    "the launcher is the package every module reads" = same installed plain.othrys.internal.agents.codex;
    "the launcher keeps codex as its program" = installed.meta.mainProgram == "codex";
    "a host can set the package" = (hmOf swapped).programs.codex.package.passthru.unwrapped.pname == "hello";
    "with the launcher off the package is llm-agents' codex itself" = same (hmOf unwrapped).programs.codex.package llmCodex && same unwrapped.othrys.internal.agents.codex llmCodex;
    "analytics, the metrics exporter, feedback and the update check are off" = !settings.analytics.enabled && settings.otel.metrics_exporter == "none" && !settings.feedback.enabled && !settings.check_for_update_on_startup;
    "telemetry can be left on" = !(telemetryOn ? analytics) && !(telemetryOn ? check_for_update_on_startup);
    "a host's settings win over the module's" = overridden.analytics.enabled && !overridden.feedback.enabled;
    "the permission profile is the module's own, asking before leaving the sandbox" = settings.default_permissions == "othrys" && settings.approval_policy == "on-request";
    "the default mode keeps the workspace read-only" = profile.extends == ":read-only";
    "acceptEdits lets the workspace be written" = accepting.permissions.othrys.extends == ":workspace";
    "the files Claude Code may not read are denied to sandboxed commands" =
      profile.filesystem.":workspace_roots"
      == {
        ".env" = "deny";
        ".env.*" = "deny";
        "secrets/**" = "deny";
      };
    "sudo and rm -rf are forbidden" = inputs.nixpkgs.lib.hasInfix ''prefix_rule(pattern = ["sudo"], decision = "forbidden"'' rules && inputs.nixpkgs.lib.hasInfix ''prefix_rule(pattern = ["rm", "-rf"], decision = "forbidden"'' rules;
    "a host's own rules follow the module's" = inputs.nixpkgs.lib.hasInfix ''pattern = ["cargo", "test"]'' withRule;
    "the rules leave default.rules to Codex" = !(hm.programs.codex.rules ? default);
    "the sign-in uses the keyring and falls back to a file" = settings.cli_auth_credentials_store == "auto";
    "config.toml stays writable and declared values win" = hm.programs.codex.mutableSettings;
    "the MCP servers are handed over" = hm.programs.codex.enableMcpIntegration && hm.programs.mcp.servers ? context7;
    "the shared context is the global AGENTS.md" = hm.programs.codex.context == plain.othrys.apps.ai.context.text;
    "a shared skill and a skill for the tool both reach Codex" = hm.programs.codex.skills ? shared-skill && hm.programs.codex.skills ? codex-only;
    "~/.codex is persisted at 0700" =
      plain.othrys.internal.persist."apps.ai.codex".user.directories
      == [
        {
          directory = ".codex";
          mode = "0700";
        }
      ];
    "the host trusts the cache the package comes from" = builtins.elem "https://cache.numtide.com" plain.nix.settings.substituters;
    "a host without the module writes nothing for it" = !(off.othrys.internal.homeConfig ? "apps.ai.codex") && !(off.othrys.internal.persist ? "apps.ai.codex") && !builtins.elem "https://cache.numtide.com" off.nix.settings.substituters;
  }
