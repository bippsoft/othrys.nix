# modules/apps/gui/floorp/default.nix
# Floorp browser, a Firefox fork with Fluent UI
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.apps.floorp;
  theme = config.othrys.theme;
  inherit (theme) palette;
  themed = palette != null;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
  dark = theme.polarity == "dark";

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
  extensionPolicy = _: ext:
    {
      install_url = "file://${pkgs.fetchurl {inherit (ext) url hash;}}";
      installation_mode = "force_installed";
    }
    // lib.optionalAttrs (ext.default_area != null) {inherit (ext) default_area;};
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

  config = lib.mkIf cfg.enable {
    # Persistence for browser profile data
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username}.directories = [
        ".floorp"
      ];
    };

    othrys.internal.homeConfig."apps.floorp" = {
      programs.floorp = {
        enable = true;

        profiles.default = {
          id = 0;
          name = "default";
          isDefault = true;

          settings = {
            # Rendering is left to the browser's own detection. The
            # WebRender prefs that once forced software mode are gone from
            # Firefox, and turning the GPU process off on every host costs
            # the ones whose driver is fine.
            "media.hardware-video-decoding.enabled" = true;

            # BetterFox - Fastfox
            "network.http.max-connections" = 1800;
            "network.http.max-persistent-connections-per-server" = 10;
            "network.http.max-urgent-start-excessive-connections-per-host" = 5;
            "network.http.pacing.requests.enabled" = false;
            "network.dnsCacheExpiration" = 3600;
            "network.dns.max_high_priority_threads" = 8;
            "network.ssl_tokens_cache_capacity" = 10240;
            "browser.cache.disk.enable" = true;
            "browser.sessionhistory.max_total_viewers" = 4;
            "browser.cache.memory.capacity" = -1;
            "browser.cache.memory.max_entry_size" = 153600;

            # BetterFox - Securefox
            "browser.contentblocking.category" = "strict";
            "urlclassifier.trackingSkipURLs" = lib.concatStringsSep ", " cfg.trackingProtectionExemptions;
            "urlclassifier.features.socialtracking.skipURLs" = lib.concatStringsSep ", " cfg.trackingProtectionExemptions;
            "signon.rememberSignons" = cfg.builtinPasswordManager;
            "network.cookie.sameSite.noneRequiresSecure" = true;
            "browser.download.start_downloads_in_tmp_dir" = true;
            "browser.helperApps.deleteTempFileOnExit" = true;
            "browser.uitour.enabled" = false;
            "privacy.globalprivacycontrol.enabled" = true;

            # BetterFox - Peskyfox
            "browser.privatebrowsing.vpnpromourl" = "";
            "extensions.getAddons.showPane" = false;
            "extensions.htmlaboutaddons.recommendations.enabled" = false;
            "browser.discovery.enabled" = false;
            "browser.shopping.experience2023.enabled" = false;
            "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = false;
            "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;
            "browser.preferences.moreFromMozilla" = false;
            "browser.tabs.tabmanager.enabled" = false;
            "browser.aboutConfig.showWarning" = false;
            "browser.aboutwelcome.enabled" = false;
            "full-screen-api.transition-duration.enter" = "0 0";
            "full-screen-api.transition-duration.leave" = "0 0";
            "full-screen-api.warning.delay" = -1;
            "full-screen-api.warning.timeout" = 0;
            "browser.urlbar.suggest.calculator" = true;
            "browser.urlbar.unitConversion.enabled" = true;
            "browser.urlbar.trending.featureGate" = false;
            "browser.newtabpage.activity-stream.feeds.topsites" = false;
            "browser.newtabpage.activity-stream.feeds.section.topstories" = false;

            # BetterFox - Smoothfox
            "general.smoothScroll" = true;
            "general.smoothScroll.msdPhysics.enabled" = true;
            "mousewheel.default.delta_multiplier_y" = 300;

            # Browser behavior
            "browser.startup.homepage" = "about:blank";
            "browser.startup.page" = 3;
            "browser.tabs.loadInBackground" = true;
            "browser.tabs.warnOnClose" = true;
            "browser.tabs.warnOnCloseOtherTabs" = true;

            # New tab page, backgrounds disabled
            "browser.startup.homepage.abouthome_cache.enabled" = false;
            "browser.newtabpage.activity-stream.newNewtabExperience.enabled" = false;
            "browser.newtabpage.activity-stream.showSponsored" = false;
            "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
            "browser.newtabpage.activity-stream.improvesearch.topSiteSearchShortcuts" = false;
            "browser.newtabpage.activity-stream.prerender" = false;
            "browser.newtabpage.activity-stream.discoverystream.enabled" = false;
            "browser.newtabpage.activity-stream.section.highlights.includeVisited" = false;
            "browser.newtabpage.activity-stream.newtabWallpapers.enabled" = false;
            "browser.newtabpage.activity-stream.feeds.section.highlights" = false;

            # Floorp UI
            "floorp.browser.user_interface" = "fluentUI";
            "floorp.design.theme" = "fluentUI";
            # The theme follows the host's polarity rather than claiming a
            # dark system on a light host.
            "browser.theme.toolbar-theme" = 2;
            "browser.theme.content-theme" = 2;
            "ui.systemUsesDarkTheme" =
              if dark
              then 1
              else 0;
            # Written only with a palette. Without one the browser keeps its
            # own page background.
            "browser.display.background_color" = lib.mkIf themed "#${palette.base00}";
            "layout.css.backdrop-filter.enabled" = false;
            "ui.prefersReducedMotion" = 0;
            "browser.tabs.animate" = true;
            "browser.fullscreen-autohide.animateUp" = 1;
            "toolkit.cosmeticAnimations.enabled" = true;
            "browser.tabs.drawInTitlebar" = true;
            "mozilla.widget.use-argb-visuals" = true;
            "layout.css.devPixelsPerPx" = "1.0";
            "browser.display.os-zoom-behavior" = 1;

            # Floorp design
            "floorp.browser.tabbar.settings" = 2;
            "floorp.browser.tabs.collapseTreeStyleTab" = false;
            "floorp.browser.sidebar.enable" = false;
            "floorp.browser.sidebar.right" = false;
            "floorp.browser.sidebar2.hide" = true;
            "browser.toolbars.bookmarks.visibility" = "never";
            "floorp.browser.roundedCorners.enabled" = true;
            "floorp.tabbar.style" = 0;
            "browser.compactmode.show" = true;
            "browser.uidensity" = 1;
            "layout.css.color-mix.enabled" = true;
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

            # Wayland
            "dom.event.clipboardevents.enabled" = true;
            "layers.async-pan-zoom.enabled" = true;
            "widget.wayland.use-egl" = true;
          };

          search = {
            force = true;
            inherit (cfg.search) default;
            engines =
              {
                "Nix Packages" = {
                  urls = [
                    {
                      template = "https://search.nixos.org/packages";
                      params = [
                        {
                          name = "type";
                          value = "packages";
                        }
                        {
                          name = "query";
                          value = "{searchTerms}";
                        }
                      ];
                    }
                  ];
                  icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                  definedAliases = ["@np"];
                };
                "NixOS Options" = {
                  urls = [
                    {
                      template = "https://search.nixos.org/options";
                      params = [
                        {
                          name = "type";
                          value = "options";
                        }
                        {
                          name = "query";
                          value = "{searchTerms}";
                        }
                      ];
                    }
                  ];
                  icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                  definedAliases = ["@no"];
                };
                "Home Manager Options" = {
                  urls = [{template = "https://home-manager-options.extranix.com/?query={searchTerms}";}];
                  definedAliases = ["@hm"];
                };
                "google".metaData.hidden = true;
                "amazondotcom-us".metaData.hidden = true;
                "bing".metaData.hidden = true;
                "ebay".metaData.hidden = true;
              }
              // cfg.search.extraEngines;
          };

          # The stylesheet styles the browser chrome through the colour
          # variables below and nothing else, so it is written only with a
          # palette. Without one the browser keeps its own chrome.
          userChrome = lib.mkIf themed (let
            rgb = theme.colors.rgb.base00;
            cssVariables = ''
              :root {
                --theme-bg: #${palette.base00} !important;
                --theme-bg-alt: #${palette.base01} !important;
                --theme-selection: #${palette.base02} !important;
                --theme-comment: #${palette.base03} !important;
                --theme-fg-dark: #${palette.base04} !important;
                --theme-fg: #${palette.base05} !important;
                --theme-fg-light: #${palette.base06} !important;
                --theme-fg-bright: #${palette.base07} !important;
                --theme-red: #${palette.base08} !important;
                --theme-orange: #${palette.base09} !important;
                --theme-yellow: #${palette.base0A} !important;
                --theme-green: #${palette.base0B} !important;
                --theme-cyan: #${palette.base0C} !important;
                --theme-blue: #${palette.base0D} !important;
                --theme-magenta: #${palette.base0E} !important;
                --theme-brown: #${palette.base0F} !important;
                --theme-border: var(--theme-comment) !important;
                --theme-surface: var(--theme-selection) !important;
                --theme-selection-bright: var(--theme-fg-dark) !important;
                --theme-bg-transparent: rgba(${toString rgb.r}, ${toString rgb.g}, ${toString rgb.b}, 0.85) !important;
                --toolbar-bgcolor: var(--theme-bg) !important;
                --toolbar-color: var(--theme-fg) !important;
                --lwt-accent-color: var(--theme-bg-alt) !important;
                --lwt-text-color: var(--theme-fg) !important;
                --theme-font-family: system-ui, -apple-system, sans-serif !important;
                --theme-animation-duration: 200ms !important;
                --theme-animation-easing: cubic-bezier(0.1, 0.9, 0.2, 1) !important;
              }
            '';
          in
            cssVariables + "\n" + builtins.readFile ./userChrome.css);

          userContent = builtins.readFile ./userContent.css;
        };

        policies = {
          ExtensionSettings =
            {
              "*" = {
                installation_mode = "blocked";
                allowed_types = ["extension"];
              };
            }
            // lib.mapAttrs extensionPolicy cfg.extensions
            // cfg.extraExtensions;
          PasswordManagerEnabled = cfg.builtinPasswordManager;
          DisableTelemetry = true;
          DisableFirefoxStudies = true;
          DisablePocket = true;
          DisableFirefoxAccounts = false;
          DontCheckDefaultBrowser = true;
          PromptForDownloadLocation = false;
          EnableTrackingProtection = {
            Value = true;
            Locked = true;
            Cryptomining = true;
            Fingerprinting = true;
            EmailTracking = true;
          };
          DisableFirefoxScreenshots = false;
          DisableFormHistory = false;
          DisablePasswordReveal = false;
          DNSOverHTTPS = {
            Enabled = false;
            Locked = false;
          };
        };
      };

      home.sessionVariables =
        {
          MOZ_ENABLE_WAYLAND = "1";
        }
        // lib.optionalAttrs (cfg.vaapiDriver != null) {
          LIBVA_DRIVER_NAME = cfg.vaapiDriver;
        }
        // lib.optionalAttrs (cfg.vaapiDriver == "nvidia") {
          NVD_BACKEND = "direct";
        };
    };
  };
}
