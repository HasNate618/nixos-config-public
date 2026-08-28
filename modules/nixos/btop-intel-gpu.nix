{ config, lib, pkgs, ... }:
let
  btop-patched = pkgs.runCommand "btop-patched" { buildInputs = [ pkgs.patchelf pkgs.btop ]; } ''
    mkdir -p $out/bin
    cp ${pkgs.btop}/bin/btop $out/bin/btop
    chmod u+w $out/bin/btop
    OLD_RPATH=$(patchelf --print-rpath $out/bin/btop)
    if [ -n "$OLD_RPATH" ]; then
      patchelf --set-rpath "$OLD_RPATH:/run/opengl-driver/lib" $out/bin/btop
    else
      patchelf --set-rpath "/run/opengl-driver/lib" $out/bin/btop
    fi
    chmod u-w $out/bin/btop
  '';
in {
  security.wrappers.btop = {
    owner = "root";
    group = "root";
    source = "${btop-patched}/bin/btop";
    capabilities = "cap_perfmon+ep";
  };
}
