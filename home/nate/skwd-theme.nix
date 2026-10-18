{ config, lib, ... }:

let
  opacity = config.theme.opacity;
  opStr = builtins.toString opacity;
  zenHex = config.theme.zenAlphaHex;
  # Kvantum: percent to reduce window/menu opacity by (1.0 -> 0%, 0.65 -> 35%)
  reducePct = builtins.toString (builtins.floor ((1.0 - opacity) * 100.0 + 0.5));
  withOpacity = fn:
    let raw = builtins.readFile (./skwd-theme-configs/templates + "/${fn}");
    in builtins.replaceStrings [ "@OPACITY@" "@OPACITY_HEX@" "@REDUCE_PCT@" ] [ opStr zenHex reducePct ] raw;

  # Templates consumed verbatim by matugen (they carry the {{colors.*}} refs).
  plainTemplates = [
    "hyprland-border-color"
    "hyprland-group-border-color"
    "quickshell-colors.json"
    "quickshell-colors.toml"
    "kitty.conf"
    "ghostty.conf"
    "kde-colors.colors"
    "vesktop.css"
    "yazi-theme.toml"
    "hyprlock-theme.conf"
    "qt6ct-colors.conf"
    "chromium.css"
    "btop.theme"
    "cava-config"
    # Focus-only variants, picked by focus-theme-render in preference to the
    # shared template above. The two palettes have different structure —
    # matugen derives every role from ONE seed hue, focus mode maps distinct
    # terminal hues — so a template that shows four different colours is right
    # under focus and wrong under matugen. These keep the two apart.
    "btop.theme-focus"
    "cava-config-focus"
    "lazygit-config.yml"
    "neovim.lua"
    "pi-theme.json"
  ];

  # Templates parameterised by the single NixOS opacity value.
  # hyprlock-theme.conf is deliberately NOT here: its input box is a fixed
  # 0.92 alpha on the darkest surface token, so it must not track theme.opacity.
  opacityTemplates = [
    "foot-colors.conf"
    "gtk-css.css"
    "gtk3-css.css"
    "gtk4-css.css"
    "swayosd.css"
    "zen-transparency.css"
    "kvantum-kvconfig"
    "kvantum-svg"
    "kvantum-alt-kvconfig"
    "kvantum-alt-svg"
  ];

  templateFile = name: {
    name = "skwd-wall-v2/matugen/templates/${name}";
    value = {
      force = true;
      source = ./skwd-theme-configs/templates + "/${name}";
    };
  };
  templateText = name: {
    name = "skwd-wall-v2/matugen/templates/${name}";
    value = {
      force = true;
      text = withOpacity name;
    };
  };
  scriptFile = name: {
    name = "skwd-wall/scripts/${name}";
    value = {
      force = true;
      executable = true;
      source = ./skwd-theme-configs/scripts + "/${name}";
    };
  };
in
{
  # skwd-wall v2 config is APP-OWNED so picker/settings changes persist: the
  # seed below is copied in on first activation (and replaces the old store
  # symlink once), then never overwritten again — rebuilds leave live config
  # alone. To bake UI-tuned values back into the repo, diff
  # ~/.config/skwd-wall-v2/config.json against skwd-theme-configs/config.json.
  home.activation.skwdWallConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    CONFIG="$HOME/.config/skwd-wall-v2/config.json"
    if [ ! -e "$CONFIG" ] || [ -L "$CONFIG" ]; then
      run rm -f "$CONFIG"
      run mkdir -p "$(dirname "$CONFIG")"
      run cp ${./skwd-theme-configs/config.json} "$CONFIG"
      run chmod u+w "$CONFIG"
    fi
  '';

  # matugen templates + pipeline scripts. Templates are resolved as bare names
  # from this dir (default for paths.templates); the package ships its own
  # fallbacks under share/skwd-wall-v2/data/matugen/templates.
  xdg.configFile =
    builtins.listToAttrs (map templateFile plainTemplates)
    // builtins.listToAttrs (map templateText opacityTemplates)
    // {
      # integration refers to "wl-kbptr-config"; source file keeps the suffix
      "skwd-wall-v2/matugen/templates/wl-kbptr-config" = {
        force = true;
        source = ./skwd-theme-configs/templates/wl-kbptr-config.conf;
      };
    }
    // builtins.listToAttrs (map scriptFile [
      "bg-sat-boost.py"
      "patch-monotheme.sh"
      "reload-kde.sh"
      "reload-niri.sh"
      "reload-zen.sh"
      "zen-red-scale.py"
    ]);
}
