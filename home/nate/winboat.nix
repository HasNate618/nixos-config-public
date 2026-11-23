# WinBoat — run Windows apps (incl. MS Project) as native-looking Linux
# windows via RemoteApp, backed by a dockur/windows VM in Docker.
#
# WHY THIS OVER WINAPPS (winapps-org/winapps): winboat is already in the pinned
# nixpkgs (26.11, v0.9.0), so it is one package entry and no new flake input, no
# cachix trusted-key, no plaintext Windows password in a checked-in config, and no
# separate manual VM-provisioning step. WinApps has Project 2021 on its
# community-tested list (pre-built icon + MIME types), but WinBoat finds it by
# scanning the Windows registry for .exe entries, so it still appears — just
# without the polished icon/MIME integration.
#
# DOCKER SOCKET: the NixOS docker module here runs with enableOnBoot = false
# (battery saving — see hosts/nixos/default.nix), but docker.socket is still
# `wantedBy = ["sockets.target"]` and is enabled+active, so the daemon is started
# on demand by the first connection to /var/run/docker.sock. That is exactly
# what WinBoat does when it launches containers from its GUI, so NO extra
# service is needed to force dockerd up. Verified live: docker.socket is
# enabled + active.
#
# Verified locally: pkgs.winboat 0.9.0 evaluates and builds; it
# pulls freerdp, docker-compose and podman-compose as runtime deps and builds
# the mingw-w64 guest_server itself. /dev/kvm present, nested virt = Y.
{ pkgs, ... }:

{
  home.packages = [ pkgs.winboat ];

  # Start the Windows container on demand the first time WinBoat is launched.
  # `docker info` is a read-only probe: with dockerd already up it exits 0 and
  # does nothing; with it down, connecting to the root:docker 0660 socket is
  # what triggers socket activation. The first run of the WinBoat install
  # wizard pulls several GB, so this keeps that off the boot path.
  #
  # NOTE: this home-manager uses the freeform Unit/Service/Install shape (same
  # as hypridle/monitor-layout-home), not the older description/wantedBy/
  # serviceConfig keys -- those are rejected by systemdUtils.types.units here.
  systemd.user.services.winboat-docker = {
    Unit = {
      Description = "Ensure dockerd is reachable for WinBoat's Windows container";
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.docker}/bin/docker info";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
