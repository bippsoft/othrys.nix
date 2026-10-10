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
    "nothing else may install" = (policies darkHost).ExtensionSettings."*".installation_mode == "blocked";
    "the built-in password manager is off" = !(policies darkHost).PasswordManagerEnabled && !(profile darkHost).settings."signon.rememberSignons";
    "tracking protection exempts nothing by default" = (profile darkHost).settings."urlclassifier.trackingSkipURLs" == "";
    "the WebRender prefs are gone" = !((profile darkHost).settings ? "gfx.webrender.all") && !((profile darkHost).settings ? "layers.gpu-process.enabled");
    "the theme follows the polarity" = (profile darkHost).settings."ui.systemUsesDarkTheme" == 1 && (profile lightHost).settings."ui.systemUsesDarkTheme" == 0;
    "no sidebar file is written" = !((hm darkHost).home.file ? ".config/floorp-sidebery/sidebery-config.json");
    "vesktop writes no Discord settings file" = !((hm vesktopHost).xdg.configFile ? "discord/settings.json");
  }
