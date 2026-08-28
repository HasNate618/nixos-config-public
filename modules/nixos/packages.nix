{ pkgs, zen-pdf-viewer, zen-markdown-viewer, ... }: {
  imports = [ ../shared/packages.nix ];

  environment.systemPackages = with pkgs; [
    # Laptop-specific CLI tools
    gh
    xh
    opencode
    python313Packages.huggingface-hub
    pi
    jcode
    mcp-proxy

    # GUI apps
    imv
    mpv
    ffmpeg
    localsend
    nmap
    swappy
    pinta
    qbittorrent
    blender
    pipes
    obs-studio
    ghostty
    libreoffice
    uwsm
    evtest

    # Custom packages
    zen-pdf-viewer
    zen-markdown-viewer
    kdePackages.kdenlive
    kdePackages.kdeconnect-kde
  ];
}
