# modules/services/mosh.darwin.nix
# The nix-darwin implementation of othrys.services.mosh
#
# A mosh client starts mosh-server over SSH, and sshd runs it as
# `<shell> -c "mosh-server new ..."`, a shell that is neither a login nor
# interactive. zsh reads nix-darwin's /etc/zshenv even then, and that file
# puts the system profile on PATH, so for an account whose shell is zsh the
# package on the system path is the whole server. A non-interactive bash
# reads no such file, so a client reaching an account with another shell
# passes `--server=/run/current-system/sw/bin/mosh-server`. The firewall
# nix-darwin manages takes no port list, so openFirewall is unread.
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [./mosh.nix];

  config = lib.mkIf config.othrys.services.mosh.enable {
    environment.systemPackages = [pkgs.mosh];
  };
}
