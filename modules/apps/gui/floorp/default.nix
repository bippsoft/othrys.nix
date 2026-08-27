# modules/apps/gui/floorp/default.nix
# Floorp browser, a Firefox fork with Fluent UI
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.floorp;
  inherit (config.lib.stylix) colors;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
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
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
        default = {};
        description = "Custom search engines merged over the curated Nix/NixOS set.";
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

    extraExtensions = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      description = "Extension policies merged over the curated set (sidebery, bitwarden, ublock, violentmonkey).";
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

    manageSidebery = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Deploy the curated Sidebery sidebar layout, overwriting the in-profile
        copy on every rebuild. Disable to manage Sidebery yourself (keeps
        changes made from within the browser).
      '';
    };
  };

  # The assertion lives in its own mkIf because the body interpolates Stylix colors,
  # so it must stay unevaluated when stylix is off or the deep Stylix error
  # preempts the assertion message during assertion collection.
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.othrys.system.stylix.enable;
          message = "othrys.apps.floorp requires othrys.system.stylix.enable = true (browser theming reads the Stylix palette).";
        }
      ];
    })
    (lib.mkIf (cfg.enable && config.othrys.system.stylix.enable) {
      # Persistence for browser profile data
      environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
        users.${username}.directories = [
          ".floorp"
        ];
      };

      home-manager.users.${username} = {
        stylix.targets.floorp = {
          enable = true;
          profileNames = ["default"];
        };

        programs.floorp = {
          enable = true;

          profiles.default = {
            id = 0;
            name = "default";
            isDefault = true;

            settings = with colors; {
              # Rendering, software mode for NVIDIA + Wayland
              "gfx.webrender.all" = false;
              "gfx.webrender.enabled" = false;
              "layers.gpu-process.enabled" = false;
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
              "urlclassifier.trackingSkipURLs" = "*.reddit.com, *.twitter.com, *.twimg.com";
              "urlclassifier.features.socialtracking.skipURLs" = "*.instagram.com, *.twitter.com, *.twimg.com";
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
              "browser.theme.toolbar-theme" = 2;
              "browser.theme.content-theme" = 2;
              "ui.systemUsesDarkTheme" = 1;
              "browser.display.background_color" = "#${base00}";
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

            userChrome = let
              cssVariables = ''
                :root {
                  --theme-bg: #${colors.base00} !important;
                  --theme-bg-alt: #${colors.base01} !important;
                  --theme-selection: #${colors.base02} !important;
                  --theme-comment: #${colors.base03} !important;
                  --theme-fg-dark: #${colors.base04} !important;
                  --theme-fg: #${colors.base05} !important;
                  --theme-fg-light: #${colors.base06} !important;
                  --theme-fg-bright: #${colors.base07} !important;
                  --theme-red: #${colors.base08} !important;
                  --theme-orange: #${colors.base09} !important;
                  --theme-yellow: #${colors.base0A} !important;
                  --theme-green: #${colors.base0B} !important;
                  --theme-cyan: #${colors.base0C} !important;
                  --theme-blue: #${colors.base0D} !important;
                  --theme-magenta: #${colors.base0E} !important;
                  --theme-brown: #${colors.base0F} !important;
                  --theme-border: var(--theme-comment) !important;
                  --theme-surface: var(--theme-selection) !important;
                  --theme-selection-bright: var(--theme-fg-dark) !important;
                  --theme-bg-transparent: rgba(${colors.base00-rgb-r}, ${colors.base00-rgb-g}, ${colors.base00-rgb-b}, 0.85) !important;
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
              cssVariables + "\n" + builtins.readFile ./userChrome.css;

            userContent = builtins.readFile ./userContent.css;
          };

          policies = {
            ExtensionSettings =
              {
                "*" = {
                  installation_mode = "blocked";
                  allowed_types = ["extension"];
                };
                "{3c078156-979c-498b-8990-85f7987dd929}" = {
                  install_url = "https://addons.mozilla.org/firefox/downloads/latest/sidebery/latest.xpi";
                  installation_mode = "force_installed";
                  default_area = "nav-bar";
                };
                "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
                  install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
                  installation_mode = "force_installed";
                };
                "uBlock0@raymondhill.net" = {
                  install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
                  installation_mode = "force_installed";
                };
                "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}" = {
                  install_url = "https://addons.mozilla.org/firefox/downloads/latest/violentmonkey/latest.xpi";
                  installation_mode = "force_installed";
                };
              }
              // cfg.extraExtensions;
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

        home.file.".config/floorp-sidebery/sidebery-config.json" = lib.mkIf cfg.manageSidebery {
          text = builtins.readFile ./sidebery.json;
          force = true;
        };
      };
    })
  ];
}
