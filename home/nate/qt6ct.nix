{ ... }: {
  # Qt6 platform theme (qt6ct). Widgets are painted by Kvantum
  # (QT_STYLE_OVERRIDE=kvantum, set by home-manager); the palette comes from
  # skwd-wall/matugen (colors/matugen.conf) — matching the GTK css colors.
  xdg.configFile."qt6ct/qt6ct.conf" = {
    force = true;
    text = ''
      [Appearance]
      color_scheme_path=/home/nate/.config/qt6ct/colors/matugen.conf
      custom_palette=false
      style=kvantum

      [Fonts]
      general="JetBrains Mono,11,-1,5,50,0,0,0,0,0"
      fixed="JetBrains Mono,11,-1,5,50,0,0,0,0,0"

      [Interface]
      dialog_buttons_have_icons=1
      double_click_interval=400
      gui_effects=medium
      keyboard_scheme=2
      menus_have_icons=true
      show_shortcuts_in_context_menus=true
      toolbutton_style=2
      underline_shortcut=1

      [Palette]
      standard_dialogs=xdgdesktopportal
    '';
  };
}
