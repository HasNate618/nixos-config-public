# Kvantum overlay: fix translucency on Wayland + workaround nixpkgs build bug.
#
# 1. The nixpkgs Kvantum patch has a substitute() call that references
#    Kvantum/style/polishing.cpp (wrong path — source root is Kvantum/).
#    This kills the build. Work around by creating a symlink before patchPhase.
#
# 2. Skip the alpha-buffer-size check on Wayland (it always fails there
#    because Qt6 Wayland windows don't have alpha in their surface format,
#    but the compositor handles alpha blending directly).
self: super: {
  qt6Packages = super.qt6Packages // {
    qtstyleplugin-kvantum = super.qt6Packages.qtstyleplugin-kvantum.overrideAttrs (old: {
      prePatch = (old.prePatch or "") + ''
        # The nixpkgs patch references Kvantum/style/polishing.cpp but the
        # source root is already Kvantum/, so the file is at style/polishing.cpp.
        # Create a symlink so the substitute() call finds it.
        if [ ! -f Kvantum/style/polishing.cpp ] && [ -f style/polishing.cpp ]; then
          mkdir -p Kvantum/style
          ln -s ../../style/polishing.cpp Kvantum/style/polishing.cpp
        fi
      '';
      postPatch = (old.postPatch or "") + ''
        # Skip the alpha-buffer-size check on Wayland (it always fails there
        # because Qt6 Wayland windows don't have alpha in their surface format,
        # but the compositor handles alpha blending directly).
        sed -i 's/if (widget->testAttribute(Qt::WA_WState_Created))/if (tspec_.isX11 \&\& widget->testAttribute(Qt::WA_WState_Created))/' style/polishing.cpp
      '';
    });
  };
}
