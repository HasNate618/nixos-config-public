{ config, lib, pkgs, ... }:

let
  dollar = "$";
in

{
  home.username = "nate";
  home.homeDirectory = "/home/nate";
  home.stateVersion = "26.05";

  home.sessionVariables = {
    XDG_COLOR_SCHEME = "dark";
    GTK_THEME = "MonoThemeDark";
    XDG_CURRENT_DESKTOP = "Hyprland";
    TERMCMD = "foot";
    XDG_SESSION_DESKTOP = "Hyprland";
  };

  home.packages = with pkgs; [
    poppler-utils
    fzf
    ghostscript
    xdg-desktop-portal-gtk
    xdg-desktop-portal-termfilechooser

    # Dev tooling
    uv                               # fast Python package/venv manager
    devenv                           # declarative dev shells per project
    go                               # Go programming language
    rustup                           # Rust toolchain installer (rustc, cargo, etc.)
    gcc                              # C/C++ compiler
    gnumake                          # make
    nil                              # Nix language server
    mise                             # polyglot version manager (node, python, go, etc.)
    nodejs                           # node.js, npm, npx
  ];

  imports = [
    ./bin.nix
    ./tmux.nix
    ./editors.nix
    ./ssh.nix
    ./hyprland.nix
    ./hypridle.nix
    ./lockscreen.nix
    ./monitor-layout-home.nix
    ./quickshell.nix
    ./zen.nix
    ./chromium.nix
    ./zsh.nix
    ./fish.nix
    ./gtk.nix
    ./dconf.nix
    ./foot.nix
    ./ghostty.nix
    ./cura.nix
    ./skwd-theme.nix
    ./git.nix
    ./herdr.nix
    ./rog.nix
    ./qt6ct.nix
  ];

  # KDE color scheme reference — points to matugen-generated SkwdMatugen.colors
  xdg.configFile."kdeglobals".force = true;
  xdg.configFile."kdeglobals".text = ''
    [General]
    ColorScheme=SkwdMatugen
    Name=SkwdMatugen
  
    [KDE]
    contrast=4
  '';

  # Default PDF handler + browser + media associations
  xdg.configFile."mimeapps.list".text = ''
    [Default Applications]
    application/pdf=zen-pdf-viewer.desktop
    text/markdown=zen-markdown-viewer.desktop
    text/x-markdown=zen-markdown-viewer.desktop
    x-scheme-handler/http=zen.desktop
    x-scheme-handler/https=zen.desktop
    text/html=zen.desktop
    application/xhtml+xml=zen.desktop

    # images
    image/png=imv.desktop
    image/jpeg=imv.desktop
    image/gif=imv.desktop
    image/webp=imv.desktop
    image/bmp=imv.desktop
    image/tiff=imv.desktop
    image/svg+xml=imv.desktop

    # video
    video/mp4=mpv.desktop
    video/x-msvideo=mpv.desktop
    video/x-matroska=mpv.desktop
    video/x-flv=mpv.desktop
    video/x-ms-wmv=mpv.desktop
    video/mpeg=mpv.desktop
    video/ogg=mpv.desktop
    video/webm=mpv.desktop
    video/quicktime=mpv.desktop
    video/3gpp=mpv.desktop
    video/3gpp2=mpv.desktop
    video/x-ms-asf=mpv.desktop
    video/x-ogm+ogg=mpv.desktop
    video/x-theora+ogg=mpv.desktop
    application/ogg=mpv.desktop

    # office documents
    application/vnd.openxmlformats-officedocument.wordprocessingml.document=libreoffice.desktop
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet=libreoffice.desktop
    application/vnd.openxmlformats-officedocument.presentationml.presentation=libreoffice.desktop
    application/vnd.ms-excel=libreoffice.desktop
    application/vnd.ms-powerpoint=libreoffice.desktop
    application/msword=libreoffice.desktop
    application/vnd.oasis.opendocument.text=libreoffice.desktop
    application/vnd.oasis.opendocument.spreadsheet=libreoffice.desktop
    application/vnd.oasis.opendocument.presentation=libreoffice.desktop
    text/csv=libreoffice.desktop

    # text / code
    text/plain=zen-markdown-viewer.desktop
    text/english=nvim.desktop
    text/x-makefile=nvim.desktop
    text/x-c++hdr=nvim.desktop
    text/x-c++src=nvim.desktop
    text/x-chdr=nvim.desktop
    text/x-csrc=nvim.desktop
    text/x-java=nvim.desktop
    text/x-moc=nvim.desktop
    text/x-pascal=nvim.desktop
    text/x-tcl=nvim.desktop
    text/x-tex=nvim.desktop
    application/x-shellscript=nvim.desktop
    text/x-c=nvim.desktop
    text/x-c++=nvim.desktop
    application/xml=nvim.desktop
    text/xml=nvim.desktop

    # directories
    inode/directory=nautilus.desktop
  '';


  # xdg-desktop-portal-termfilechooser -- yazi as system file picker
  # swayosd OSD theme — matugen-generated via skwd-wall (template: swayosd.css)
  xdg.configFile."xdg-desktop-portal-termfilechooser/config".text = ''
    [filechooser]
    cmd=/home/nate/.config/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh
    default_dir=/home/nate
  '';

  xdg.configFile."xdg-desktop-portal/portals.conf".text = ''
    [preferred]
    default=hyprland
    org.freedesktop.impl.portal.ScreenCast=hyprland
    org.freedesktop.impl.portal.Screenshot=hyprland
    org.freedesktop.impl.portal.FileChooser=termfilechooser
  '';

  xdg.configFile."hypr/xdph.conf".text = ''
    screencopy {
      custom_picker_binary = hyprland-preview-share-picker
    }
  '';


  # Fish conf.d -- keybindings, functions (Nix '' strings mangle escape sequences)
  xdg.configFile."fish/conf.d/keybindings.fish".text = ''
    # Vim mode
    set -g fish_key_bindings fish_vi_key_bindings
    set -g fish_escape_delay_ms 10
    set -g fish_vi_force_default_mode insert

    # Ctrl-A/Ctrl-E for home/end in insert mode
    bind -M insert \ca beginning-of-line
    bind -M insert \ce end-of-line

    # Alt+Enter to accept autosuggestion and execute
    bind -M insert \e\r 'commandline -f accept-autosuggestion; commandline -f execute'

    # Ctrl+Backspace/Delete to delete whole words
    bind -M insert \ch backward-kill-word
    bind -M insert \e\[3\;5~ kill-word
    bind -M default \ch backward-kill-word
    bind -M default \e\[3\;5~ kill-word

    # Alt+Up to cd to parent
    bind -M insert \e\[1\;3A 'cd ..; commandline -f repaint'
    bind -M default \e\[1\;3A 'cd ..; commandline -f repaint'

    # ... abbreviation
    abbr -a \.\.\. "cd ../.."
  '';

  xdg.configFile."fish/conf.d/sudo-last.fish".text = ''
    # sudo !! -- re-run last command with sudo
    function sudo
        if test "$argv" = "!!"
            command sudo $history[1]
        else
            command sudo $argv
        end
    end
  '';

  xdg.configFile."fish/conf.d/mkcd.fish".text = ''
    function mkcd
        mkdir -p $argv[1]
        and cd $argv[1]
    end
  '';

  xdg.configFile."fish/conf.d/yazi.fish".text = ''
    function y
        set tmp (mktemp -t "yazi-cwd.XXXXXX")
        set yazi_cmd $argv
        yazi $yazi_cmd --cwd-file="$tmp"
        if test -f "$tmp"; and [ (cat "$tmp") != (pwd) ]
            cd (cat $tmp)
        end
        rm -f $tmp
    end
  '';


  # Opencode config — MCP servers
  xdg.configFile."opencode/opencode.jsonc" = {
    force = true;
    text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    theme = "system";
    plugin = [
      "superpowers@git+https://github.com/obra/superpowers.git"
    ];
    mcp = {
      trawl = {
        type = "remote";
        url = "http://trawl.home.lab/mcp";
      };
    };
  }; };

  # Foot terminal
  xdg.configFile."foot/foot.ini".text = ''
    font=JetBrainsMono Nerd Font:size=11
    pad=14x14
    shell=fish
    include=~/.config/foot/colors.ini

    [cursor]
    style=block
    blink=no

    [mouse]
    hide-when-typing=yes
  '';

  # Yazi file manager
  xdg.configFile."yazi/yazi.toml".text = ''
    [mgr]
    sort_by = "mtime"
    sort_reverse = true
    sort_dir_first = true
    show_hidden = false

    [opener]
    pdf = [ { run = 'zen-pdf-viewer "$1"', orphan = true, for = "unix" } ]
    image = [ { run = 'imv "$1"', orphan = true, for = "unix" } ]
    video = [ { run = 'mpv "$1"', orphan = true, for = "unix" } ]
    audio = [ { run = 'mpv "$1"', orphan = true, for = "unix" } ]
    text = [ { run = 'nvim "$1"', block = true, for = "unix" } ]
    markdown = [ { run = 'zen-markdown-viewer "$1"', orphan = true, for = "unix" } ]
    extract = [ { run = 'ya pub extract --list "$@"', for = "unix" } ]
    html = [ { run = 'xdg-open "$1"', orphan = true, for = "unix" } ]

    [open]
    rules = [
      { url = "**/*.md",              use = [ "markdown" ] },
      { mime = "text/markdown",       use = [ "markdown" ] },
      { mime = "inode/x-empty",       use = [ "text" ] },
      { mime = "application/zip",          use = [ "extract" ] },
      { mime = "application/x-tar",       use = [ "extract" ] },
      { mime = "application/gzip",        use = [ "extract" ] },
      { mime = "application/x-bzip2",     use = [ "extract" ] },
      { mime = "application/x-xz",        use = [ "extract" ] },
      { mime = "application/x-zstd",      use = [ "extract" ] },
      { mime = "application/x-7z-compressed", use = [ "extract" ] },
      { mime = "application/vnd.rar",     use = [ "extract" ] },
      { url = "**/*.html",             use = [ "html" ] },
      { mime = "text/*",           use = [ "text" ] },
      { mime = "application/json", use = [ "text" ] },
      { mime = "application/xml",  use = [ "text" ] },
      { mime = "application/pdf",  use = [ "pdf" ] },
      { mime = "image/*",          use = [ "image" ] },
      { mime = "video/*",          use = [ "video" ] },
      { mime = "audio/*",          use = [ "audio" ] },
    ]

    [plugin]
    prepend_previewers = [
      { url = "*.csv",    run = "rich-preview" },
      { url = "*.md",     run = "rich-preview" },
      { url = "*.rst",    run = "rich-preview" },
      { url = "*.ipynb",  run = "rich-preview" },
      { url = "*.json",   run = "rich-preview" },
      { url = "*/{mime=audio/*}", run = "mediainfo" },
      { url = "*/{mime=video/*}", run = "mediainfo" },
      { url = "*/{mime=image/*}", run = "mediainfo" },
    ]
    prepend_preloaders = [
      { url = "*/{mime=audio/*}", run = "mediainfo" },
      { url = "*/{mime=video/*}", run = "mediainfo" },
      { url = "*/{mime=image/*}", run = "mediainfo" },
    ]

    prepend_fetchers = [
      { url = "*",   run = "git", group = "git" },
      { url = "*/",  run = "git", group = "git" },
    ]
  '';

  xdg.configFile."yazi/keymap.toml".text = ''
    [mgr]

    [[mgr.prepend_keymap]]
    on  = "u"
    run = 'open --hovered'
    desc = "Extract archive"


    [[mgr.prepend_keymap]]
    on  = "R"
    run = "plugin recycle-bin"
    desc = "Recycle bin menu"

    [[mgr.prepend_keymap]]
    on   = [ "c", "a", "a" ]
    run  = 'shell -- cd "$(dirname %h)" && zip -r "$(basename %h).zip" "$(basename %h)"'
    desc = "Archive selected files"

    [[mgr.prepend_keymap]]
    on   = [ "c", "a", "p" ]
    run  = 'shell -- cd "$(dirname %h)" && 7z a "$(basename %h).7z" "$(basename %h)"'
    desc = "Archive selected files (password)"

    [[mgr.prepend_keymap]]
    on   = [ "c", "a", "l" ]
    run  = 'shell -- cd "$(dirname %h)" && zip -r "$(basename %h).zip" "$(basename %h)" -9'
    desc = "Archive selected files (compression level)"

    [[mgr.prepend_keymap]]
    on  = "M"
    run = "plugin mount"
    desc = "Mount/unmount disks"

    [[mgr.prepend_keymap]]
    on  = "!"
    run = 'shell \"$SHELL\" --block'
    desc = "Open $SHELL here"

    [[mgr.prepend_keymap]]
    on  = "e"
    run = "shell 'nvim %h' --block"
    desc = "Edit in nvim"


    [[mgr.prepend_keymap]]
    on  = "o"
    run = "open --hovered"
    desc = "Open with configured opener"
    [[mgr.prepend_keymap]]
    on  = "E"
    run = "shell -- xdg-open %h"
    desc = "Open with system default"
  '';

  xdg.configFile."yazi/init.lua".text = ''
    require("full-border"):setup()
    require("recycle-bin"):setup()
    require("git"):setup { order = 1500 }
  '';

  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;
      command_timeout = 200;
      format = "[${dollar}{directory}${dollar}{git_branch}${dollar}{git_status}](${dollar}{style})${dollar}{character}";

      character = {
        error_symbol = "[✗](bold cyan)";
        success_symbol = "[❯](bold cyan)";
      };

      directory = {
        truncation_length = 2;
        truncation_symbol = "…/";
        repo_root_style = "bold cyan";
        repo_root_format = "[${dollar}{repo_root}](${dollar}{repo_root_style})[${dollar}{path}](${dollar}{style})[${dollar}{read_only}](${dollar}{read_only_style}) ";
      };

      git_branch = {
        format = "[${dollar}{branch}](${dollar}{style}) ";
        style = "italic cyan";
      };

      git_status = {
        format = "[${dollar}{all_status}](${dollar}{style})";
        style = "cyan";
        ahead = "⇡${dollar}{count} ";
        diverged = "⇕⇡${dollar}{ahead_count}⇣${dollar}{behind_count} ";
        behind = "⇣${dollar}{count} ";
        conflicted = " ";
        up_to_date = " ";
        untracked = "? ";
        modified = " ";
        stashed = "";
        staged = "";
        renamed = "";
        deleted = "";
      };
    };
  };
}
