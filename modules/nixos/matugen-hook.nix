{ config, lib, pkgs, ... }:

# matugen-hook — LD_PRELOAD shim for skwd-daemon.
#
# skwd-daemon spawns its bundled matugen 4.0.0 (pinned in PATH by the
# skwd-wall package), which crashes headless on achromatic images and has no
# working fallback color. The hook (built from ./matugen-hook.c) redirects
# every exec of `matugen` to ~/.local/bin/matugen, the wrapper that runs
# matugen 4.1.0 with --source-color-index 0 and --fallback-color '#00FF00'.
#
# Reference the package from other modules:
#   LD_PRELOAD="${config.services.matugen-hook.package}/lib/matugen-hook.so"

let
  cfg = config.services.matugen-hook;

  matugenHook = pkgs.stdenv.mkDerivation {
    pname = "matugen-hook";
    version = "2.0.0";
    src = ./matugen-hook.c;
    phases = [ "buildPhase" ];
    buildPhase = ''
      mkdir -p $out/lib
      gcc -shared -fPIC -O2 -o $out/lib/matugen-hook.so $src -ldl
    '';
  };
in {
  options.services.matugen-hook.package = lib.mkOption {
    type = lib.types.package;
    default = matugenHook;
    description = ''
      LD_PRELOAD hook that redirects bare `matugen` execs to the
      ~/.local/bin/matugen wrapper (fixes headless crashes on
      monochrome wallpapers in skwd-daemon).
    '';
  };

  config = {
    environment.systemPackages = [ cfg.package ];
  };
}
