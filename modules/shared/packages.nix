# Shared CLI tools — imported by all machines (laptop, server, etc.)
{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    # Shell
    fish
    starship
    zoxide

    # File navigation
    eza
    bat
    ripgrep
    fd
    fzf
    tree

    # System monitoring
    htop
    btop

    # Archives / files
    unzip
    xz
    file
    which
    killall

    # Download / network
    curl
    wget

    # Version control
    git

    # Editors
    neovim

    # Terminal
    tmux

    # Data / formats
    jq
    yq-go
    csvlens
    jless

    # Misc
    fastfetch
    tldr
    dust
    duf
    ncdu
    p7zip          # 7z archive support
    zip            # zip archive support
    lazygit
    mediainfo
    trash-cli
    unrar
    lazydocker
    udisks2
    yazi
  ];
}
