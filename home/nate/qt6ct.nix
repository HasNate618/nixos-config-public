{ ... }: {
  # Qt6 application style/theme config
  xdg.configFile."qt6ct/qt6ct.conf" = {
    force = true;
    text = ''
      [Appearance]
      color_scheme_path=/home/nate/.config/qt6ct/colors/darker.ini
      custom_palette=false
      style=kvantum-dark

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

  # Darker color scheme (fallback for non-matugen apps)
  xdg.configFile."qt6ct/colors/darker.ini" = {
    force = true;
    text = ''
      [ColorScheme]
      name=Darker
      author=Nate
      description=A dark color scheme matching MonoThemeDark

      [Colors:Button]
      background=@Variant(\0\0\0\x84\0\0\0\x14\0\0\0\x30\0\0\0\x30)
      background_normal=@Variant(\0\0\0\x84\0\0\0\x14\0\0\0\x30\0\0\0\x30)

      [Colors:View]
      background=@Variant(\0\0\0\x84\0\0\0\x18\0\0\0\x18\0\0\0\x12\0\0\0\x10)
      background_normal=@Variant(\0\0\0\x84\0\0\0\x18\0\0\0\x18\0\0\0\x12\0\0\0\x10)

      [Colors:Window]
      background=@Variant(\0\0\0\x84\0\0\0\x18\0\0\0\x18\0\0\0\x12\0\0\0\x10)
      background_normal=@Variant(\0\0\0\x84\0\0\0\x18\0\0\0\x18\0\0\0\x12\0\0\0\x10)

      [Colors:Selection]
      background=@Variant(\0\0\0\x84\0\0\0\x14\0\0\0\x30\0\0\0\x30)
      background_normal=@Variant(\0\0\0\x84\0\0\0\x14\0\0\0\x30\0\0\0\x30)
    '';
  };
}
