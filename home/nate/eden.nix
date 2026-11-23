# Eden — Nintendo Switch emulator (a Yuzu fork), packaged from the official
# AppImage. Upstream ships no NixOS build and docs/user/QuickStart.md covers
# only Windows/SteamDeck/macOS. docs/user/ThirdParty.md links a community flake
# (Grantimatter/eden-flake), but it is pinned to v0.1.1 while stable is v0.2.1
# and its last two Cachix CI runs failed, so the substituter has no current
# build.
#
# NOTE ON WRAPPING: this AppImage is compressed with DWARFS, not squashfs, so
# nixpkgs' appimageTools.extract (unsquashfs) fails on it with "Can't find a
# valid SQUASHFS superblock" — do not "fix" that by switching to
# appimageTools.wrapType2. It runs as a self-mounting binary instead, which is
# fine on NixOS: the runtime is static-pie, needs no FHS chroot, and resolves the
# host's Vulkan ICDs — which is what makes the NVIDIA GPU work.
#
# Verified locally: launches, detects the host CPU, and lands on the dGPU
# (the NVIDIA render node is used; the Intel one is left untouched).
# Upstream forces the X11 backend by default
# via its wayland-is-broken.hook, so it runs under XWayland — that is upstream's
# choice, not a limitation of this packaging.
#
# Two derivations, not one: the launcher has to name the AppImage's store path,
# and a derivation cannot reference its own output path ("infinite recursion").
#
# To bump: update `version`, re-hash the AppImage
# (nix hash file --type sha256 --sri <file>), and replace ./eden-icon.svg with
# the icon from the new image.
{ pkgs, ... }:

let
  version = "0.2.1";

  appimage = pkgs.fetchurl {
    url = "https://stable.eden-emu.dev/v${version}/Eden-Linux-v${version}-amd64-clang-pgo.AppImage";
    hash = "sha256-eii/mIsGSIMZiXIr26qQqzE3G0A4CBmYE+DqfIslum0=";
  };

  # Stage 1: the executable itself, kept out of $out/bin so that `eden` on PATH
  # is always the wrapper below and never the raw image.
  runtime = pkgs.runCommand "eden-runtime-${version}" { } ''
    mkdir -p $out
    cp ${appimage} $out/eden.AppImage
    chmod +x $out/eden.AppImage
    touch $out
  '';

  # Stage 2: the user-facing package.
  eden = pkgs.runCommand "eden-${version}" { } ''
    mkdir -p $out/bin $out/share/applications \
             $out/share/icons/hicolor/scalable/apps
    cp ${./eden-icon.svg} \
      $out/share/icons/hicolor/scalable/apps/dev.eden_emu.eden.svg

    # Launcher. Two jobs, both from upstream's own documentation:
    #
    # 1. nvidia-offload sets __NV_PRIME_RENDER_OFFLOAD,
    #    __GLX_VENDOR_LIBRARY_NAME and __VK_LAYER_NV_optimus — all of which are
    #    silently ignored when the dGPU is powered off, same as the
    #    ~/.local/bin/steam wrapper, so no battery-specialisation guard is
    #    needed here.
    # 2. The GL knobs below. __GL_THREADED_OPTIMIZATIONS is upstream-documented
    #    for the OpenGL backend (docs/user/Graphics.md) and is inert under the
    #    default Vulkan backend. The shader-cache pair works around Switch
    #    titles blowing past the 128MB default and recompiling every launch,
    #    which reads as a stutter on load — same values as the Steam and
    #    gamescope-bigpicture wrappers.
    #
    # Battery boot: nvidia module is blacklisted, so fall back to iGPU.
    #
    # Kept in a launcher rather than the systemd user env so a bad value is one
    # edit away, not a logout — upstream recommends the same (docs/user/Basics.md).
    cat > $out/bin/eden <<'EDEN_WRAPPER'
    #!${pkgs.runtimeShell}
    export __GL_THREADED_OPTIMIZATIONS=1
    export __GL_SHADER_DISK_CACHE_SIZE=12000000000
    export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
    if [ -d /proc/driver/nvidia ] && command -v nvidia-offload >/dev/null 2>&1; then
      exec nvidia-offload ${runtime}/eden.AppImage "$@"
    else
      exec ${runtime}/eden.AppImage "$@"
    fi
    EDEN_WRAPPER
    chmod +x $out/bin/eden

    # Upstream's own desktop entry (from inside the AppImage), with Exec routed
    # through the wrapper and the icon name matching the file installed above.
    # The MimeTypes are what make a double-clicked NSP/XCI/NRO/NSO dump open
    # in Eden.
    cat > $out/share/applications/eden.desktop <<'EDEN_DESKTOP'
    [Desktop Entry]
    Type=Application
    Name=Eden
    GenericName=Switch Emulator
    Comment=Nintendo Switch emulator
    Icon=dev.eden_emu.eden
    TryExec=eden
    Exec=eden %F
    Categories=Game;Emulator;Qt;
    MimeType=application/x-nx-nro;application/x-nx-nso;application/x-nx-nsp;application/x-nx-xci;
    Keywords=Nintendo;Switch;
    StartupWMClass=eden
    EDEN_DESKTOP

    touch $out
  '';
in

{
  home.packages = [ eden ];
}
