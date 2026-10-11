# modules/theme/schemes/oxocarbon.nix
# Oxocarbon as a base24 scheme, in both polarities
#
# Adapted from the Oxocarbon theme by Shaunsingh, with every colour taken from
# IBM's Carbon palette. Each line names the Carbon colour it holds. base00 to
# base0F are the base16 colours, and base10 to base17 are the bright ANSI
# colours base24 adds.
{
  dark = {
    base00 = "161616"; # IBM Gray 100 (Background)
    base01 = "262626"; # IBM Gray 90 (Lighter Bg)
    base02 = "393939"; # IBM Gray 80 (Selection)
    base03 = "525252"; # IBM Gray 70 (Comments)
    base04 = "6f6f6f"; # IBM Gray 60 (Dark Fg)
    base05 = "f4f4f4"; # IBM Gray 10 (Default Fg)
    base06 = "ffffff"; # White (Light Fg)
    base07 = "e0e0e0"; # IBM Gray 20 (Light Bg)
    base08 = "fa4d56"; # IBM Red 50 (Red)
    base09 = "ff832b"; # IBM Orange 40 (Orange)
    base0A = "f1c21b"; # IBM Yellow 30 (Yellow)
    base0B = "42be65"; # IBM Green 40 (Green)
    base0C = "3ddbd9"; # IBM Teal 30 (Cyan/Teal)
    base0D = "4589ff"; # IBM Blue 50 (Blue)
    base0E = "be95ff"; # IBM Purple 40 (Purple)
    base0F = "ff7eb6"; # IBM Magenta 40 (Magenta)
    base10 = "525252"; # Bright Black (Gray 70)
    base11 = "ff8389"; # Bright Red (Red 40)
    base12 = "6fdc8c"; # Bright Green (Green 30)
    base13 = "fddc69"; # Bright Yellow (Yellow 20)
    base14 = "78a9ff"; # Bright Blue (Blue 40)
    base15 = "d4bbff"; # Bright Purple (Purple 30)
    base16 = "08bdba"; # Bright Cyan (Teal 40)
    base17 = "ffffff"; # Bright White
  };
  light = {
    base00 = "ffffff"; # White (Background)
    base01 = "f4f4f4"; # IBM Gray 10 (Darker Bg)
    base02 = "e0e0e0"; # IBM Gray 20 (Selection)
    base03 = "a8a8a8"; # IBM Gray 40 (Comments)
    base04 = "6f6f6f"; # IBM Gray 60 (Darker Fg)
    base05 = "161616"; # IBM Gray 100 (Default Fg)
    base06 = "262626"; # IBM Gray 90 (Lighter Fg)
    base07 = "161616"; # IBM Gray 100 (Dark Bg)
    base08 = "da1e28"; # IBM Red 60 (Red)
    base09 = "ba4e00"; # IBM Orange 60 (Orange)
    base0A = "b28600"; # IBM Yellow 50 (Yellow)
    base0B = "198038"; # IBM Green 60 (Green)
    base0C = "005d5d"; # IBM Teal 70 (Cyan/Teal)
    base0D = "0f62fe"; # IBM Blue 60 (Blue)
    base0E = "8a3ffc"; # IBM Purple 60 (Purple)
    base0F = "d12771"; # IBM Magenta 60 (Magenta)
    base10 = "8d8d8d"; # Bright Black (Gray 50)
    base11 = "fa4d56"; # Bright Red (Red 50)
    base12 = "24a148"; # Bright Green (Green 50)
    base13 = "d2a106"; # Bright Yellow (Yellow 40)
    base14 = "4589ff"; # Bright Blue (Blue 50)
    base15 = "a56eff"; # Bright Purple (Purple 50)
    base16 = "009d9a"; # Bright Cyan (Teal 50)
    base17 = "161616"; # Bright White (Black)
  };
}
