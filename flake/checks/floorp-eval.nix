# flake/checks/floorp-eval.nix
# CORE. What the Floorp and Discord modules hand Home Manager, read back from
# evaluated hosts. The extension policy once pointed at unpinned latest.xpi
# downloads, the sidebar file it wrote was never read, the password manager
# stayed on beside Bitwarden, four sites were exempt from tracking protection
# on every host, and two clients wrote the same Discord settings file.
{
  hostConfig,
  mkExpectations,
  functioningHost,
}: let
  host = polarity:
    hostConfig [
      functioningHost
      {
        othrys.system.stylix = {
          enable = true;
          inherit polarity;
        };
        othrys.apps.floorp.enable = true;
      }
    ];
  darkHost = host "dark";
  lightHost = host "light";
  # The option's own example, one extension merged over the default set.
  withUserscripts = hostConfig [
    functioningHost
    ({options, ...}: {
      othrys.system.stylix.enable = true;
      othrys.apps.floorp = {
        enable = true;
        extensions =
          options.othrys.apps.floorp.extensions.default
          // {
            "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}" = {
              url = "https://addons.mozilla.org/firefox/downloads/file/5009389/violentmonkey-2.49.0.xpi";
              hash = "sha256-dh6moyzueMMmPRm72CHq/U6gci8Q/zWOy6JznFv/dvs=";
            };
          };
      };
    })
  ];
  vesktopHost = hostConfig [
    functioningHost
    {othrys.apps.vesktop.enable = true;}
  ];
  hm = h: h.home-manager.users.${h.othrys.system.user.name};
  profile = h: (hm h).programs.floorp.profiles.default;
  policies = h: (hm h).programs.floorp.policies;
  extensions = h: builtins.attrValues (builtins.removeAttrs (policies h).ExtensionSettings ["*"]);
  fromStore = e: builtins.match "file:///nix/store/.*[.]xpi" e.install_url != null;
in
  mkExpectations "othrys-eval-floorp" {
    "every extension installs from a store path" = extensions darkHost != [] && builtins.all fromStore (extensions darkHost);
    "the default set is Sidebery, Bitwarden and uBlock Origin" =
      builtins.attrNames (builtins.removeAttrs (policies darkHost).ExtensionSettings ["*"])
      == ["uBlock0@raymondhill.net" "{3c078156-979c-498b-8990-85f7987dd929}" "{446900e4-71c2-419f-a6a7-df9c091e268b}"];
    "Violentmonkey is not installed by default" = !((policies darkHost).ExtensionSettings ? "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}");
    "a host can add an extension over the default set" = (policies withUserscripts).ExtensionSettings ? "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}" && (policies withUserscripts).ExtensionSettings ? "uBlock0@raymondhill.net";
    "nothing else may install" = (policies darkHost).ExtensionSettings."*".installation_mode == "blocked";
    "the built-in password manager is off" = !(policies darkHost).PasswordManagerEnabled && !(profile darkHost).settings."signon.rememberSignons";
    "tracking protection exempts nothing by default" = (profile darkHost).settings."urlclassifier.trackingSkipURLs" == "";
    "the WebRender prefs are gone" = !((profile darkHost).settings ? "gfx.webrender.all") && !((profile darkHost).settings ? "layers.gpu-process.enabled");
    "the theme follows the polarity" = (profile darkHost).settings."ui.systemUsesDarkTheme" == 1 && (profile lightHost).settings."ui.systemUsesDarkTheme" == 0;
    "no sidebar file is written" = !((hm darkHost).home.file ? ".config/floorp-sidebery/sidebery-config.json");
    "vesktop writes no Discord settings file" = !((hm vesktopHost).xdg.configFile ? "discord/settings.json");
  }
