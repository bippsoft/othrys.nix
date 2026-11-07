# modules/apps/gui/floorp/floorp.nix
# Floorp browser, a Firefox fork with Fluent UI
{
  lib,
  pkgs,
  ...
}: let
  # Each extension is fetched at build time by hash and installed from the
  # store, so the browser never downloads an unpinned latest.xpi and the
  # policy names a file whose content is fixed. A bump is a new URL and hash.
  extensionType = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.str;
        description = "Versioned download URL of the signed .xpi.";
        example = "https://addons.mozilla.org/firefox/downloads/file/4903712/sidebery-5.6.1.xpi";
      };
      hash = lib.mkOption {
        type = lib.types.str;
        description = "SRI hash of the file at `url`.";
        example = "sha256-6KCktVarfdU2iXwYFq+dCRgDAiMGjqZoOgQ3YQOmyvI=";
      };
      default_area = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Where the extension's button is placed, as the policy's `default_area`.";
        example = "navbar";
      };
    };
  };
in {
  imports = [
    (lib.mkRemovedOptionModule ["othrys" "apps" "floorp" "manageSidebery"] "The sidebar layout file it wrote was never read by the extension, which keeps its state inside the profile.")
  ];

  options.othrys.apps.floorp = {
    enable = lib.mkEnableOption "Floorp browser";

    search = {
      default = lib.mkOption {
        type = lib.types.str;
        default = "ddg";
        description = "Default search engine (home-manager engine id or a key from extraEngines).";
        example = "Kagi";
      };

      extraEngines = lib.mkOption {
        # The type Home Manager gives programs.firefox.profiles.<name>.search.engines,
        # which serialises each engine to JSON. A value that cannot be
        # serialised is refused under this option's name.
        type = lib.types.attrsOf (lib.types.attrsOf (pkgs.formats.json {}).type);
        default = {};
        description = "Custom search engines merged over the curated Nix/NixOS set. Each engine is an attribute set of JSON values, in the shape of Home Manager's `programs.firefox.profiles.<name>.search.engines`.";
        example = lib.literalExpression ''
          {
            "Kagi" = {
              urls = [{template = "https://kagi.com/search?q={searchTerms}";}];
              definedAliases = ["@k"];
            };
          }
        '';
      };
    };

    extensions = lib.mkOption {
      type = lib.types.attrsOf extensionType;
      default = {
        "{3c078156-979c-498b-8990-85f7987dd929}" = {
          url = "https://addons.mozilla.org/firefox/downloads/file/4903712/sidebery-5.6.1.xpi";
          hash = "sha256-6KCktVarfdU2iXwYFq+dCRgDAiMGjqZoOgQ3YQOmyvI=";
          default_area = "navbar";
        };
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          url = "https://addons.mozilla.org/firefox/downloads/file/5076543/bitwarden_password_manager-2026.9.3.xpi";
          hash = "sha256-XdbvpdIo2+rHoMaog/lReH3GbleYUyLOVJIQsN+NBUw=";
        };
        "uBlock0@raymondhill.net" = {
          url = "https://addons.mozilla.org/firefox/downloads/file/5034826/ublock_origin-1.75.0.xpi";
          hash = "sha256-W3RBWGBFY3BkS9gPFhJehlsObDVrtd/PuEBpln6qUoc=";
        };
      };
      defaultText = lib.literalMD "Sidebery, Bitwarden and uBlock Origin at pinned versions";
      example = lib.literalExpression ''
        options.othrys.apps.floorp.extensions.default
        // {
          "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}" = {
            url = "https://addons.mozilla.org/firefox/downloads/file/5009389/violentmonkey-2.49.0.xpi";
            hash = "sha256-dh6moyzueMMmPRm72CHq/U6gci8Q/zWOy6JznFv/dvs=";
          };
        }
      '';
      description = ''
        Extensions force-installed from the Nix store, keyed by extension id.
        Each is fetched at build time by URL and hash, so the set a host runs
        is the set its configuration names. A definition replaces the default
        set, so a host that adds one extension merges it over
        `options.othrys.apps.floorp.extensions.default`, as the example does
        for Violentmonkey.

        A userscript manager such as Violentmonkey is left to the host. Every
        script it installs runs with page access on the sites it matches, can
        make cross-origin requests and updates itself from its own URL, which
        is more code execution than the rest of the set together.
      '';
    };

    builtinPasswordManager = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Firefox's own password manager. Off, since Bitwarden is in the default extension set and two managers prompt on every form.";
    };

    trackingProtectionExemptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["*.example.com"];
      description = "Sites exempt from tracking protection and social-tracking blocking. Empty, so a host names its own exceptions.";
    };

    extraExtensions = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      description = "Raw extension policies merged over the set built from `extensions`, for an entry that needs a policy shape the typed option does not cover.";
      example = lib.literalExpression ''
        {
          "search@kagi.com" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/kagi-search-for-firefox/latest.xpi";
            installation_mode = "force_installed";
          };
        }
      '';
    };

    vaapiDriver = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "nvidia";
      description = ''
        Value for LIBVA_DRIVER_NAME used for hardware video decode. Null (the
        default) leaves it unset so the system-wide VA-API default applies; set
        "nvidia" on NVIDIA hosts (which also enables the nvidia-vaapi direct
        backend).
      '';
    };
  };
}
