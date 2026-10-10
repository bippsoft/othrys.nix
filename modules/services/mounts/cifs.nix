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
        type = lib.types.enum ["none" "krb5" "krb5i" "ntlmv2" "ntlmv2i" "ntlmssp" "ntlmsspi"];
        default = "ntlmssp";
        description = "Authentication mode, one of the values mount.cifs accepts for `sec=`. The `i` variants also sign every packet.";
      };

      vers = lib.mkOption {
        type = lib.types.enum ["1.0" "2.0" "2.1" "3" "3.0" "3.0.2" "3.1.1" "default"];
        default = "3.1.1";
        example = "3.0";
        description = ''
          SMB protocol version passed as `vers=`. The default pins the newest
          dialect, so a server cannot negotiate the mount down to an older
          one. `default` hands the choice back to the kernel, and an old NAS
          needs the dialect it speaks named here.
        '';
      };

      seal = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Encrypt the session with `seal`. Authentication protects the
          password and nothing else, so without it file contents cross the
          network in the clear. Encryption needs SMB 3.0 or newer on both
          ends, and a share on an older dialect sets this to false.
        '';
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
    assertions =
      lib.mapAttrsToList (name: share: {
        assertion = share.seal -> !builtins.elem share.vers ["1.0" "2.0" "2.1"];
        message = "othrys.services.mounts.cifs.shares.${name}: seal needs SMB 3.0 or newer and vers is ${share.vers}. Raise vers, or set seal = false to mount without encryption.";
      })
      cfg.shares;

    environment.systemPackages = [pkgs.cifs-utils];

    fileSystems = lib.mapAttrs' (_: share:
      lib.nameValuePair share.mountPoint {
        device = share.remotePath;
        fsType = "cifs";
        options =
          [
            "credentials=${share.credentialsFile}"
            "uid=${toString share.uid}"
            "gid=${toString share.gid}"
            "sec=${share.sec}"
            "vers=${share.vers}"
            "file_mode=0644"
            "dir_mode=0755"
            # A file server is not a source of setuid binaries or device nodes.
            "nosuid"
            "nodev"
          ]
          ++ lib.optional share.seal "seal"
          ++ [
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
