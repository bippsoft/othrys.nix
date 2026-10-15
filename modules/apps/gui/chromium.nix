# modules/apps/gui/chromium.nix
# Ungoogled Chromium for the primary user, with extensions from pinned CRX files
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.chromium;

  # Chromium accepts one to four unsigned 16-bit components, with no leading
  # zeroes, and refuses an all-zero version. Check here so the host gets the
  # othrys option name rather than an extension that silently fails to load.
  extensionVersion =
    lib.types.addCheck
    (lib.types.strMatching "(0|[1-9][0-9]*)(\\.(0|[1-9][0-9]*)){0,3}")
    (version: let
      components = map builtins.fromJSON (lib.splitString "." version);
    in
      lib.all (component: component <= 65535) components
      && lib.any (component: component > 0) components);

  extensionType = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.strMatching "https://.+";
        description = "Download URL of a signed CRX artifact at a fixed version.";
        example = "https://example.com/extensions/example-1.0.crx";
      };
      hash = lib.mkOption {
        type = lib.types.strMatching "sha256-[A-Za-z0-9+/]{43}=";
        description = "SHA-256 SRI hash of the CRX file at `url`.";
        example = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      version = lib.mkOption {
        type = extensionVersion;
        description = "Version in the CRX manifest, with one to four components between 0 and 65535 and at least one nonzero component.";
        example = "1.0";
      };
    };
  };

  # A local CRX works without Google update requests, which Ungoogled Chromium
  # blocks. Direct artifact URLs and hashes also keep a newer Web Store upload
  # from changing what a rebuild fetches.
  extensionConfig = id: extension: {
    inherit id;
    inherit (extension) version;
    crxPath = pkgs.fetchurl {
      inherit (extension) url hash;
      name = "chromium-extension-${id}-${extension.version}.crx";
    };
  };
in {
  # ANCHOR: chromium-options
  options.othrys.apps.chromium = {
    enable = lib.mkEnableOption "Ungoogled Chromium browser";

    package = lib.mkPackageOption pkgs "ungoogled-chromium" {
      extraDescription = "A replacement must support Home Manager's Chromium wrapper and use Chromium's profile directory layout.";
    };

    commandLineArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["--ozone-platform=wayland"];
      description = "Launch arguments passed through Home Manager's Chromium package wrapper. Empty leaves browser and GPU detection unchanged.";
    };

    extensions = lib.mkOption {
      type = lib.types.attrsOf extensionType;
      default = {};
      example = lib.literalExpression ''
        {
          aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = {
            url = "https://example.com/extensions/example-1.0.crx";
            hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            version = "1.0";
          };
        }
      '';
      description = ''
        Extensions installed from local signed CRX files, keyed by their
        32-character IDs using the letters a through p. Each is fetched at
        build time from `url` and checked against `hash`, so the URL must keep
        serving that exact file. A release asset or a versioned path does, and
        a content delivery link that the publisher replaces on each upload
        does not.
      '';
    };
  };
  # ANCHOR_END: chromium-options

  config = lib.mkIf cfg.enable {
    assertions =
      lib.mapAttrsToList (id: _: {
        assertion = builtins.match "[a-p]{32}" id != null;
        message = "othrys.apps.chromium.extensions: '${id}' must be a 32-character extension ID using only a through p";
      })
      cfg.extensions;

    othrys.internal.persist."apps.chromium" = {
      user.directories = [
        {
          directory = ".config/chromium";
          mode = "0700";
        }
      ];
    };

    othrys.internal.homeConfig."apps.chromium" = {
      programs.chromium = {
        enable = true;
        inherit (cfg) package commandLineArgs;
        extensions = lib.mapAttrsToList extensionConfig cfg.extensions;
      };
    };
  };
}
