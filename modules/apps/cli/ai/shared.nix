# modules/apps/cli/ai/shared.nix
# What every assistant receives, which is the skills and the global context
#
# A skill is a directory holding a SKILL.md, in the Agent Skills layout that
# each assistant under this directory reads. It is declared here once and
# every enabled assistant module hands it to its own tool. A skill meant for
# one tool alone goes to that tool's own `skills` option.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.apps.ai;

  # The root wipe is a property of the host, so the line about it is
  # rendered from the host's impermanence setting rather than told to every
  # host. It is appended to the store bullet, the last of the "cannot do"
  # list, and eval-claude-code reads the rendered text back so an edit to
  # that bullet is noticed.
  storeBullet = "- **No modifying /nix/store**: It's read-only and immutable\n";
  impermanenceBullet =
    lib.optionalString config.othrys.system.impermanence.enable
    "- **No persistent writes outside $HOME**: the root filesystem is wiped on every boot, and only paths the host declares as persistent survive it\n";
  # The data bullet is rendered the same way. Only a host that wipes its root
  # has to keep data in the home directory, so the reason is added there and
  # every other host reads the plain suggestion.
  dataBullet = "- **Store data**: In `$HOME` (~/.config, ~/.local, project directories)\n";
  impermanenceDataBullet = "- **Store data**: Only in `$HOME` (~/.config, ~/.local, project directories), since anything written elsewhere is gone after a reboot\n";
  nixosContext =
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

  # The name rule of the Agent Skills format. A tool that enforces it skips
  # a skill whose directory is named otherwise, without an error.
  validName = name: builtins.match "[a-z0-9]+(-[a-z0-9]+)*" name != null && builtins.stringLength name <= 64;
  invalidNames = builtins.filter (name: !validName name) (builtins.attrNames cfg.skills);
in {
  imports = [
    (lib.mkRemovedOptionModule ["othrys" "apps" "ai" "mcp" "context"] "The context is not tied to an MCP server. Read othrys.apps.ai.context.text, and add a host's own lines with othrys.apps.ai.context.extra.")
  ];

  options.othrys.apps.ai = {
    skills = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.str lib.types.path);
      default = {};
      example = lib.literalExpression ''
        {
          release-notes = ./skills/release-notes;
          commit = '''
            ---
            name: commit
            description: Write a commit message for the staged change.
            ---
            Read the staged diff and write the message.
          ''';
        }
      '';
      description = ''
        Skills handed to every enabled assistant, keyed by skill name. A value
        is the text of a `SKILL.md`, the path of one, or the path of a
        directory that holds one. The name is the directory the skill is
        written to, so it is lower-case letters, digits and single hyphens,
        at most 64 characters, and matches the `name` in the frontmatter.

        A skill for one tool alone goes to that tool's own option, such as
        `othrys.apps.ai.claude-code.skills`.
      '';
    };

    context = {
      nixos.enable =
        lib.mkEnableOption "the text that tells an assistant it runs on NixOS, and what that rules out"
        // {default = true;};

      extra = lib.mkOption {
        type = lib.types.lines;
        default = "";
        example = ''
          # House rules

          Commit messages follow Conventional Commits.
        '';
        description = "The host's own lines, appended to the global context of every enabled assistant.";
      };

      text = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = lib.concatStringsSep "\n" (
          lib.optional cfg.context.nixos.enable nixosContext
          ++ lib.optional (cfg.context.extra != "") cfg.context.extra
        );
        defaultText = lib.literalMD "the text of `nixos-context.md` beside this module while `context.nixos.enable` is on, with a line about the root wipe added when `othrys.system.impermanence.enable` is set, followed by `context.extra`";
        description = "The global context every enabled assistant receives (derived; do not set).";
      };
    };
  };

  config.assertions = [
    {
      assertion = invalidNames == [];
      message = "othrys.apps.ai.skills: ${lib.concatStringsSep ", " invalidNames} cannot name a skill. A name is lower-case letters, digits and single hyphens, at most 64 characters.";
    }
  ];
}
