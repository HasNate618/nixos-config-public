{ pkgs, zen-pdf-viewer, zen-markdown-viewer, ... }: {
  imports = [ ../shared/packages.nix ];

  environment.systemPackages = with pkgs; [
    # Laptop-specific CLI tools
    gh
    glow                           # markdown renderer (glow --pager in yazi)
    xh
    opencode
    python313Packages.huggingface-hub
    pi
    mcp-proxy
    awscli2
    android-tools                     # adb — Android phone access (Android/data etc)

    # GUI apps
    imv
    upscayl                        # AI image upscaler (Real-ESRGAN GUI)
    mpv
    ffmpeg
    guvcview
    localsend
    luanti                          # voxel game (was imperative nix profile install)
    nmap
    swappy
    pipes
    ghostty
    libreoffice
    uwsm
    evtest

    # Custom packages
    zen-pdf-viewer
    zen-markdown-viewer
    kdePackages.kdeconnect-kde

    # Keyboard-driven mouse pointer (Wayland)
    wl-kbptr
  ];
}
