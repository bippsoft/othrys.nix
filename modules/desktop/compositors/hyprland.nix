# modules/desktop/compositors/hyprland.nix
#
# Hyprland 0.5x reads a Lua config (`~/.config/hypr/hyprland.lua`), while hyprlang
# is the legacy provider. Every setting here is expressed as an `hl.*` call
# through Home Manager's Lua renderer (`configType = "lua"`), which also drops
# a `.luarc.json` pointing at the compositor's own Lua stubs for editor
# completion. Option values that used to be hyprlang strings are structured
# attrsets now, because that is what the `hl.*` functions take.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.desktop.compositors.hyprland;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  hlLua = import ./hyprland-lua.nix {inherit lib;};
  inherit (hlLua) execCmd;

  # Mirrors home-manager's Hyprland settings value type so the freeform
  # escape hatches below accept anything the Lua renderer can emit. The
  # description override is load-bearing, since without it rendering the option
  # docs recurses forever building `oneOf`'s description from its own.
  luaValue = with lib.types;
    nullOr (oneOf [
      bool
      int
      float
      str
      path
      (attrsOf luaValue)
      (listOf luaValue)
    ])
    // {
      description = "Hyprland configuration value.";
    };

  # A single action keybinding. The module defines the dispatcher and the
  # consumer picks the chord (or null to drop the bind entirely).
  bindOpt = default: action:
    lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      inherit default;
      description = "Key chord for ${action}; null disables the bind.";
    };

  mkBind = key: dispatcher:
    lib.optional (key != null) (hlLua.mkBind {inherit key dispatcher;});

  # The catch-all monitor rule has an empty output and matches every
  # connector, so pinning workspaces to it is meaningless.
  monitorOutput = m:
    if m.output == ""
    then null
    else m.output;

  # A workspace rule, bound to a monitor only when the rule names one.
  workspaceRule = n: output: isDefault:
    {workspace = toString n;}
    // lib.optionalAttrs (output != null) {monitor = output;}
    // lib.optionalAttrs isDefault {default = true;};

  # Generate workspace assignments from the monitor config, so all ten
  # workspaces on a single monitor, split 1-5/6-10 across two.
  defaultWorkspaces = let
    outputs = map monitorOutput cfg.monitors;
    at = i:
      if builtins.length outputs > i
      then builtins.elemAt outputs i
      else null;
  in
    if builtins.length cfg.monitors <= 1
    then map (n: workspaceRule n (at 0) (n == 1)) (lib.range 1 10)
    else
      map (n: workspaceRule n (at 0) (n == 1)) (lib.range 1 5)
      ++ map (n: workspaceRule n (at 1) false) (lib.range 6 10);

  screenshotFile = "${cfg.screenshots.directory}/$(date +'%Y%m%d_%H%M%S').png";
in {
  # ANCHOR: hyprland-options
  options.othrys.desktop.compositors.hyprland = {
    enable = lib.mkEnableOption "Hyprland window manager";

    monitors = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        freeformType = lib.types.attrsOf luaValue;
        options = {
          output = lib.mkOption {
            type = lib.types.str;
            description = "Connector name, or \"\" for the catch-all rule covering every unnamed output.";
            example = "DP-1";
          };
          mode = lib.mkOption {
            type = lib.types.str;
            default = "preferred";
            description = "Resolution and refresh rate.";
            example = "1920x1080@360";
          };
          position = lib.mkOption {
            type = lib.types.str;
            default = "auto";
            description = "Position in the monitor layout.";
            example = "0x0";
          };
          scale = lib.mkOption {
            type = lib.types.str;
            default = "auto";
            description = "Scale factor.";
            example = "1";
          };
        };
      });
      default = [{output = "";}];
      description = "hl.monitor() specs. Freeform keys (vrr, transform, mirror, disabled, ...) pass through.";
      example = [
        {
          output = "DP-1";
          mode = "1920x1080@360";
          position = "0x0";
          scale = "1";
        }
        {
          output = "HDMI-A-1";
          mode = "1920x1080@144";
          position = "-1920x0";
          scale = "1";
        }
      ];
    };

    workspaces = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        freeformType = lib.types.attrsOf luaValue;
        options.workspace = lib.mkOption {
          type = lib.types.str;
          description = "Workspace the rule applies to; Hyprland requires a string selector.";
          example = "1";
        };
      });
      default = [];
      description = "hl.workspace_rule() specs (auto-generated from `monitors` if empty).";
      example = [
        {
          workspace = "1";
          monitor = "DP-1";
          default = true;
        }
      ];
    };

    mainMod = lib.mkOption {
      type = lib.types.str;
      default = "SUPER";
      description = "Modifier bound to the `mainMod` Lua local used by all default keybindings.";
    };

    terminal = lib.mkOption {
      type = lib.types.str;
      default = "kitty";
      description = "Terminal emulator command bound to the `terminal` Lua local.";
    };

    browser = lib.mkOption {
      type = lib.types.str;
      default = "firefox";
      description = "Browser command bound to the `browser` Lua local.";
    };

    input.keyboardLayout = lib.mkOption {
      type = lib.types.str;
      default = "us";
      description = "XKB keyboard layout.";
    };

    screenshots.directory = lib.mkOption {
      type = lib.types.str;
      default = "~/Pictures/Screenshots";
      description = "Directory the screenshot binds save into.";
    };

    # Curated actions with configurable chords. The module knows how to focus,
    # swap, screenshot, etc. Consumers only decide which keys trigger them.
    # Chords use Hyprland's `+`-separated syntax; `$mainMod` expands to the
    # `mainMod` option.
    binds = {
      focusLeft = bindOpt "$mainMod + H" "focus window left";
      focusRight = bindOpt "$mainMod + L" "focus window right";
      focusDown = bindOpt "$mainMod + J" "focus window down";
      focusUp = bindOpt "$mainMod + K" "focus window up";

      swapLeft = bindOpt "$mainMod + SHIFT + H" "swap window left";
      swapRight = bindOpt "$mainMod + SHIFT + L" "swap window right";
      swapDown = bindOpt "$mainMod + SHIFT + J" "swap window down";
      swapUp = bindOpt "$mainMod + SHIFT + K" "swap window up";

      killActive = bindOpt "$mainMod + Q" "close the active window";
      terminal = bindOpt "$mainMod + Return" "launch the terminal";
      browser = bindOpt "$mainMod + F" "launch the browser";

      fullscreen = bindOpt "$mainMod + M" "toggle fullscreen";
      toggleFloating = bindOpt "$mainMod + V" "toggle floating";
      pseudo = bindOpt "$mainMod + P" "toggle pseudotiling";
      pin = bindOpt "$mainMod + Y" "pin window";
      exit = bindOpt "$mainMod + SHIFT + E" "exit Hyprland";

      specialWorkspace = bindOpt "$mainMod + S" "toggle the special workspace";
      moveToSpecialWorkspace = bindOpt "$mainMod + SHIFT + S" "move window to the special workspace";
      workspacePrev = bindOpt "$mainMod + CTRL + left" "previous workspace";
      workspaceNext = bindOpt "$mainMod + CTRL + right" "next workspace";

      screenshot = bindOpt "Print" "screenshot the full screen";
      screenshotRegion = bindOpt "$mainMod + Print" "screenshot a region";
      screenshotRegionToClipboard = bindOpt "$mainMod + SHIFT + Print" "screenshot a region to the clipboard";
    };

    numberedWorkspaceBinds = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Generate $mainMod+1..0 workspace switch and $mainMod+SHIFT+1..0 move binds.";
    };

    extraBinds = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          key = lib.mkOption {
            type = lib.types.str;
            description = "Key chord; `$mainMod` expands to the mainMod option.";
            example = "$mainMod + CTRL + 1";
          };
          dispatcher = lib.mkOption {
            type = lib.types.str;
            description = "Raw Lua dispatcher expression handed to hl.bind().";
            example = "hl.dsp.focus({ monitor = \"DP-1\" })";
          };
          opts = lib.mkOption {
            type = lib.types.attrsOf luaValue;
            default = {};
            description = "hl.bind() option table (locked, repeating, mouse, description, ...).";
          };
        };
      });
      default = [];
      description = "Extra keybindings (e.g., monitor focus for multi-monitor).";
    };

    windowRules = {
      workspaceAssignments = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf luaValue);
        default = [];
        description = "hl.window_rule() specs pinning applications to workspaces, a per-fleet workflow choice, so no defaults.";
        example = [
          {
            match.class = "^(code-url-handler)$";
            workspace = "3 silent";
          }
          {
            match.class = "^(discord)$";
            workspace = "6 silent";
          }
        ];
      };

      presets = {
        steam = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Float Steam dialogs (Friends List, Settings, Steam Guard, ...) and tile the main window.";
        };
        jetbrains = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Focus/centering fixes for JetBrains IDE popup windows.";
        };
        floatCommonDialogs = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Float utility dialogs (pavucontrol, nm-connection-editor, calculator).";
        };
        pictureInPicture = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Float, pin, and corner-position Picture-in-Picture windows.";
        };
      };

      extra = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf luaValue);
        default = [];
        description = "Additional hl.window_rule() specs appended after presets.";
      };
    };

    touchpad = {
      enable = lib.mkEnableOption "Touchpad support (for laptops)";
    };
  };
  # ANCHOR_END: hyprland-options

  # Border colors and theming read the Stylix palette, and without the othrys
  # stylix module the eval dies deep inside Stylix ("one of stylix.image or
  # stylix.base16Scheme must be set"). The assertion lives in its own mkIf and
  # the body is additionally gated on stylix, so the assertion message is what
  # surfaces instead of the deep Stylix error.
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.othrys.system.stylix.enable;
          message = "othrys.desktop.compositors.hyprland requires othrys.system.stylix.enable = true (compositor theming reads the Stylix palette).";
        }
      ];

      # This host runs a graphical session, and modules key GUI behavior on this.
      othrys.desktop.graphical = true;
    })
    (lib.mkIf (cfg.enable && config.othrys.system.stylix.enable) {
      environment.systemPackages = with pkgs; [
        grim
        slurp
        wl-clipboard
        cliphist
        playerctl
        nautilus
      ];

      programs.uwsm.waylandCompositors.hyprland = lib.mkIf config.othrys.desktop.uwsm.enable {
        prettyName = "Hyprland";
        comment = "Hyprland compositor managed by UWSM";
        binPath = "/run/current-system/sw/bin/Hyprland";
      };
      othrys.desktop.login.defaultDesktop = lib.mkIf config.othrys.desktop.login.enable (lib.mkDefault "hyprland-uwsm.desktop");

      environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
        users.${username}.directories = [
          ".config/hypr"
        ];
      };

      programs.hyprland = {
        enable = true;
        withUWSM = true;
        package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
      };

      systemd.user.services.hyprpolkitagent = {
        description = "Hyprland Polkit Authentication Agent.";
        partOf = ["graphical-session.target"];
        after = ["graphical-session.target"];
        unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
        serviceConfig = {
          ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
          Slice = "session.slice";
          TimeoutStopSec = "5s";
          Restart = "on-failure";
        };
        wantedBy = ["graphical-session.target"];
      };

      nix.settings = {
        substituters = ["https://hyprland.cachix.org"];
        trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
      };

      home-manager.users.${username} = {
        wayland.windowManager.hyprland = {
          enable = true;

          package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;

          systemd.enable = !config.othrys.desktop.uwsm.enable;

          # Hyprland's own config language, while hyprlang is the legacy provider.
          # Pinned explicitly so the generated config does not follow
          # home-manager's stateVersion-dependent default.
          configType = "lua";

          settings = {
            # Rendered as Lua locals ahead of everything else, so binds and
            # any consumer `extraConfig` can reference them by name.
            mainMod = {_var = cfg.mainMod;};
            terminal = {_var = cfg.terminal;};
            browser = {_var = cfg.browser;};

            env = [
              {_args = ["XCURSOR_SIZE" "24"];}
              {_args = ["HYPRCURSOR_SIZE" "24"];}
              {_args = ["EDITOR" config.othrys.system.defaultEditor];}
              {_args = ["TERM" "xterm-256color"];}
            ];

            monitor = cfg.monitors;

            # hyprlang's exec-once, and the compositor fires this once per start.
            on = [
              {
                _args = [
                  "hyprland.start"
                  (lib.generators.mkLuaInline ''
                    function()
                      hl.exec_cmd("wl-paste --watch cliphist store")
                      hl.dispatch(hl.dsp.focus({ workspace = 1 }))
                    end'')
                ];
              }
            ];

            config = {
              input = {
                kb_layout = cfg.input.keyboardLayout;
                follow_mouse = 1;
                repeat_rate = 50;
                repeat_delay = 300;

                touchpad = lib.mkIf cfg.touchpad.enable {
                  natural_scroll = true;
                  disable_while_typing = true;
                  tap_to_click = true;
                  drag_lock = false;
                  scroll_factor = 1.0;
                };

                sensitivity = 0;
                accel_profile = "flat";
                force_no_accel = true;
              };

              general = {
                gaps_in = 5;
                gaps_out = 20;
                border_size = 1;
                resize_on_border = false;
                allow_tearing = false;
                layout = "dwindle";
                # Written with the dotted key Stylix uses, so mkForce lands on
                # the same definition instead of emitting a second Lua entry.
                "col.active_border" = lib.mkForce "rgb(${config.lib.stylix.colors.base06})";
                "col.inactive_border" = lib.mkForce "rgb(${config.lib.stylix.colors.base01})";
              };

              dwindle = {
                preserve_split = true;
                split_width_multiplier = 1.0;
                force_split = 2;
                smart_split = false;
                smart_resizing = true;
              };

              decoration = {
                rounding = 10;
                active_opacity = 1.0;
                inactive_opacity = 1.0;

                shadow = {
                  enabled = true;
                  range = 4;
                  render_power = 3;
                };

                blur = {
                  enabled = true;
                  size = 3;
                  passes = 1;
                  vibrancy = 0.1696;
                };
              };

              misc = {
                disable_hyprland_logo = true;
                disable_splash_rendering = true;
                disable_watchdog_warning = true;
              };

              animations.enabled = true;
            };

            # Curves must exist before the animations referencing them;
            # home-manager's `importantPrefixes` default puts `curve` first.
            curve = [
              {
                _args = [
                  "easeOutQuint"
                  {
                    type = "bezier";
                    points = [[0.23 1] [0.32 1]];
                  }
                ];
              }
              {
                _args = [
                  "quick"
                  {
                    type = "bezier";
                    points = [[0.15 0] [0.1 1]];
                  }
                ];
              }
              {
                _args = [
                  "almostLinear"
                  {
                    type = "bezier";
                    points = [[0.5 0.5] [0.75 1.0]];
                  }
                ];
              }
              {
                _args = [
                  "linear"
                  {
                    type = "bezier";
                    points = [[0 0] [1 1]];
                  }
                ];
              }
            ];

            animation = [
              {
                leaf = "global";
                enabled = true;
                speed = 10;
                bezier = "default";
              }
              {
                leaf = "windows";
                enabled = true;
                speed = 4.79;
                bezier = "easeOutQuint";
              }
              {
                leaf = "fade";
                enabled = true;
                speed = 3.03;
                bezier = "quick";
              }
              {
                leaf = "workspaces";
                enabled = true;
                speed = 1.94;
                bezier = "almostLinear";
                style = "fade";
              }
            ];

            # ANCHOR: hyprland-keybindings
            bind = let
              b = cfg.binds;
            in
              lib.optionals cfg.numberedWorkspaceBinds (
                map (n:
                  hlLua.mkBind {
                    key = "$mainMod + ${toString (lib.mod n 10)}";
                    dispatcher = "hl.dsp.focus({ workspace = ${toString n} })";
                  }) (lib.range 1 10)
                ++ map (n:
                  hlLua.mkBind {
                    key = "$mainMod + SHIFT + ${toString (lib.mod n 10)}";
                    dispatcher = "hl.dsp.window.move({ workspace = ${toString n} })";
                  }) (lib.range 1 10)
              )
              ++ mkBind b.focusLeft ''hl.dsp.focus({ direction = "left" })''
              ++ mkBind b.focusRight ''hl.dsp.focus({ direction = "right" })''
              ++ mkBind b.focusDown ''hl.dsp.focus({ direction = "down" })''
              ++ mkBind b.focusUp ''hl.dsp.focus({ direction = "up" })''
              ++ mkBind b.swapLeft ''hl.dsp.window.swap({ direction = "left" })''
              ++ mkBind b.swapRight ''hl.dsp.window.swap({ direction = "right" })''
              ++ mkBind b.swapDown ''hl.dsp.window.swap({ direction = "down" })''
              ++ mkBind b.swapUp ''hl.dsp.window.swap({ direction = "up" })''
              ++ mkBind b.killActive "hl.dsp.window.close()"
              ++ mkBind b.terminal "hl.dsp.exec_cmd(terminal)"
              ++ mkBind b.browser "hl.dsp.exec_cmd(browser)"
              ++ mkBind b.fullscreen "hl.dsp.window.fullscreen()"
              ++ mkBind b.toggleFloating "hl.dsp.window.float()"
              ++ mkBind b.pseudo "hl.dsp.window.pseudo()"
              ++ mkBind b.pin "hl.dsp.window.pin()"
              ++ mkBind b.exit "hl.dsp.exit()"
              ++ mkBind b.specialWorkspace ''hl.dsp.workspace.toggle_special("magic")''
              ++ mkBind b.moveToSpecialWorkspace ''hl.dsp.window.move({ workspace = "special:magic" })''
              ++ mkBind b.workspacePrev ''hl.dsp.focus({ workspace = "e-1" })''
              ++ mkBind b.workspaceNext ''hl.dsp.focus({ workspace = "e+1" })''
              ++ mkBind b.screenshot (execCmd "grim ${screenshotFile}")
              ++ mkBind b.screenshotRegion (execCmd ''grim -g "$(slurp)" ${screenshotFile}'')
              ++ mkBind b.screenshotRegionToClipboard (execCmd ''grim -g "$(slurp)" - | wl-copy'')
              # Drag binds, where `mouse` is exclusive with locked/repeating.
              ++ [
                (hlLua.mkBind {
                  key = "$mainMod + mouse:272";
                  dispatcher = "hl.dsp.window.drag()";
                  opts.mouse = true;
                })
                (hlLua.mkBind {
                  key = "$mainMod + mouse:273";
                  dispatcher = "hl.dsp.window.resize()";
                  opts.mouse = true;
                })
                (hlLua.mkBind {
                  key = "$mainMod + mouse_down";
                  dispatcher = ''hl.dsp.focus({ workspace = "e+1" })'';
                })
                (hlLua.mkBind {
                  key = "$mainMod + mouse_up";
                  dispatcher = ''hl.dsp.focus({ workspace = "e-1" })'';
                })
              ]
              # Media and brightness keys stay live on the lock screen and
              # repeat while held.
              ++ map (spec:
                hlLua.mkBind {
                  inherit (spec) key dispatcher;
                  opts = {
                    locked = true;
                    repeating = true;
                  };
                }) [
                {
                  key = "XF86AudioRaiseVolume";
                  dispatcher = execCmd "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
                }
                {
                  key = "XF86AudioLowerVolume";
                  dispatcher = execCmd "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
                }
                {
                  key = "XF86AudioMute";
                  dispatcher = execCmd "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
                }
                {
                  key = "XF86AudioMicMute";
                  dispatcher = execCmd "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
                }
                {
                  key = "XF86MonBrightnessUp";
                  dispatcher = execCmd "brightnessctl s 10%+";
                }
                {
                  key = "XF86MonBrightnessDown";
                  dispatcher = execCmd "brightnessctl s 10%-";
                }
              ]
              ++ map (spec:
                hlLua.mkBind {
                  inherit (spec) key dispatcher;
                  opts.locked = true;
                }) [
                {
                  key = "XF86AudioNext";
                  dispatcher = execCmd "playerctl next";
                }
                {
                  key = "XF86AudioPrev";
                  dispatcher = execCmd "playerctl previous";
                }
                {
                  key = "XF86AudioPlay";
                  dispatcher = execCmd "playerctl play-pause";
                }
                {
                  key = "XF86AudioPause";
                  dispatcher = execCmd "playerctl play-pause";
                }
              ]
              ++ map hlLua.mkBind cfg.extraBinds;
            # ANCHOR_END: hyprland-keybindings

            workspace_rule =
              if cfg.workspaces != []
              then cfg.workspaces
              else defaultWorkspaces;

            # ANCHOR: hyprland-windowrules
            window_rule =
              cfg.windowRules.workspaceAssignments
              ++ lib.optionals cfg.windowRules.presets.steam [
                {
                  match = {
                    class = "^(steam)$";
                    title = "^(Steam)$";
                  };
                  tile = true;
                }
                {
                  match = {
                    class = "^(steam)$";
                    title = "^(Friends List).*$";
                  };
                  float = true;
                }
                {
                  match = {
                    class = "^(steam)$";
                    title = "^(.*Settings)$";
                  };
                  float = true;
                }
                {
                  match = {
                    class = "^(steam)$";
                    title = "^(Steam Guard.*)$";
                  };
                  float = true;
                }
                {
                  match = {
                    class = "^(steam)$";
                    title = "^(Steam - News.*)$";
                  };
                  float = true;
                }
                {
                  match = {
                    class = "^(steam)$";
                    title = "^(Install.*)$";
                  };
                  float = true;
                }
              ]
              ++ lib.optionals cfg.windowRules.presets.jetbrains [
                {
                  match = {
                    class = "^(jetbrains-toolbox)$";
                    float = false;
                  };
                  no_initial_focus = true;
                }
                {
                  match = {
                    class = "^(jetbrains-.*)$";
                    float = false;
                  };
                  no_initial_focus = true;
                }
                {
                  match = {
                    class = "^(jetbrains-.*)$";
                    title = "^$";
                    initial_title = "^$";
                    float = false;
                  };
                  no_initial_focus = true;
                }
                {
                  match = {
                    class = "^(jetbrains-.*)$";
                    initial_title = "(.+)";
                    float = false;
                  };
                  center = true;
                }
                {
                  match = {
                    class = "^(jetbrains-.*)$";
                    title = "^$";
                    initial_title = "^$";
                    float = false;
                  };
                  center = true;
                }
                {
                  match = {
                    class = "^(jetbrains-.*)$";
                    title = "^win(.*)$";
                    initial_title = "^win.*$";
                    float = false;
                  };
                  no_initial_focus = true;
                }
              ]
              ++ lib.optionals cfg.windowRules.presets.floatCommonDialogs [
                {
                  match.class = "^(pavucontrol)$";
                  float = true;
                }
                {
                  match.class = "^(nm-connection-editor)$";
                  float = true;
                }
                {
                  match.title = "^(Volume Control)$";
                  float = true;
                }
                {
                  match.class = "^(org.gnome.Calculator)$";
                  float = true;
                }
              ]
              # One rule now that effects share a spec, instead of the four
              # separate hyprlang lines this replaces.
              ++ lib.optional cfg.windowRules.presets.pictureInPicture {
                match.title = "^(Picture-in-Picture)$";
                float = true;
                pin = true;
                size = "640 360";
                move = "100%-660 100%-380";
              }
              ++ cfg.windowRules.extra;
            # ANCHOR_END: hyprland-windowrules
          };
        };
      };
    })
  ];
}
