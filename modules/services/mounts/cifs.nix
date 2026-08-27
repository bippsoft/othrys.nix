# modules/services/mounts/cifs.nix
# CIFS/SMB network share mounting
{
  config,
  lib,
  pkgs,
  ...
}: let
  othrysTypes = import ../../lib/types.nix {inherit lib;};
  cfg = config.othrys.services.mounts.cifs;

  shareType = lib.types.submodule ({name, ...}: {
    options = {
      remotePath = lib.mkOption {
        type = lib.types.str;
        example = "//192.168.1.100/media";
        description = "Remote CIFS/SMB path.";
      };

      credentialsFile = lib.mkOption {
        type = othrysTypes.secretPath;
        description = "Path to a runtime credentials file (username=x\\npassword=y). Use a sops template path, not a /nix/store path.";
      };

      uid = lib.mkOption {
        type = lib.types.int;
        default = 1000;
        description = "Owner UID for mounted files.";
      };

      gid = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Owner GID for mounted files.";
      };

      sec = lib.mkOption {
        type = lib.types.str;
        default = "ntlmssp";
        description = "CIFS security/authentication mode.";
      };

      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/shares/${name}";
        defaultText = lib.literalExpression ''"/mnt/shares/<name>"'';
        description = "Local mount point.";
      };
    };
  });
in {
  # ANCHOR: cifs-options
  options.othrys.services.mounts.cifs = {
    enable = lib.mkEnableOption "CIFS/SMB network share mounts";

    shares = lib.mkOption {
      type = lib.types.attrsOf shareType;
      default = {};
      description = "CIFS/SMB shares to mount, keyed by mount name.";
    };
  };
  # ANCHOR_END: cifs-options

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.cifs-utils];

    fileSystems = lib.mapAttrs' (_: share:
      lib.nameValuePair share.mountPoint {
        device = share.remotePath;
        fsType = "cifs";
        options = [
          "credentials=${share.credentialsFile}"
          "uid=${toString share.uid}"
          "gid=${toString share.gid}"
          "sec=${share.sec}"
          "file_mode=0644"
          "dir_mode=0755"
          "_netdev"
          "nofail"
          "x-systemd.automount"
          "x-systemd.idle-timeout=60"
          "x-systemd.mount-timeout=10"
        ];
      })
    cfg.shares;
  };
}
