# modules/apps/gui/floorp/floorp.nixos.nix
# The NixOS implementation of othrys.apps.floorp
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.floorp;
  theme = config.othrys.theme;
  inherit (theme) palette;
  themed = palette != null;
  dark = theme.polarity == "dark";

  extensionPolicy = _: ext:
    {
      install_url = "file://${pkgs.fetchurl {inherit (ext) url hash;}}";
      installation_mode = "force_installed";
    }
    // lib.optionalAttrs (ext.default_area != null) {inherit (ext) default_area;};
in {
  imports = [./floorp.nix];

  config = lib.mkIf cfg.enable {
    # Persistence for browser profile data
    othrys.internal.persist."apps.floorp" = {
      user.directories = [
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
