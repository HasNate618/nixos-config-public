{ config, lib, pkgs, ... }: {
  home.packages = with pkgs; [
    quickshell
    matugen
    python3
    yq
    pamixer
    fd
    ffmpeg
    imagemagick
    qt6.qtmultimedia
    inotify-tools
    adwaita-icon-theme
    (writeShellScriptBin "quickshell-theme-push" ''
      COLORS_FILE="$HOME/.config/quickshell/colors.toml"
      [ -f "$COLORS_FILE" ] || exit 0
      PAYLOAD=$(${pkgs.python3}/bin/python3 -c "
import json, re, sys
colors = {}
with open('$COLORS_FILE') as f:
    for line in f:
        m = re.match(r'\s*(\w+)\s*=\s*\"([^\"]+)\"', line)
        if m: colors[m[1].lower()] = m[2]
print(json.dumps({'name': 'matugen', 'colors': colors}))
" 2>/dev/null)
      if [ -n "$PAYLOAD" ]; then
        ${pkgs.quickshell}/bin/qs -c desktop ipc call theme apply "$PAYLOAD" 2>/dev/null
      fi
    '')
  ];

  # Cursor theme — Adwaita (black with white outline)
  home.pointerCursor = {
    package = pkgs.adwaita-icon-theme;
    name = "Adwaita";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  # Deploy quickshell QML configs from the repo.
  # colors.toml is generated at runtime by skwd-wall matugen integration.
  xdg.configFile."quickshell/desktop/shell.qml".force = true; xdg.configFile."quickshell/desktop/shell.qml".source = ./quickshell-configs/desktop/shell.qml;
  xdg.configFile."quickshell/desktop/Theme.qml".force = true; xdg.configFile."quickshell/desktop/Theme.qml".source = ./quickshell-configs/desktop/Theme.qml;
  xdg.configFile."quickshell/desktop/Palette.js".force = true; xdg.configFile."quickshell/desktop/Palette.js".source = ./quickshell-configs/desktop/Palette.js;
  xdg.configFile."quickshell/desktop/Data.js".force = true; xdg.configFile."quickshell/desktop/Data.js".source = ./quickshell-configs/desktop/Data.js;
  xdg.configFile."quickshell/desktop/Navbar.qml".force = true; xdg.configFile."quickshell/desktop/Navbar.qml".source = ./quickshell-configs/desktop/Navbar.qml;
  xdg.configFile."quickshell/desktop/NavbarApps.qml".force = true; xdg.configFile."quickshell/desktop/NavbarApps.qml".source = ./quickshell-configs/desktop/NavbarApps.qml;
  xdg.configFile."quickshell/desktop/OmniMenu.qml".force = true; xdg.configFile."quickshell/desktop/OmniMenu.qml".source = ./quickshell-configs/desktop/OmniMenu.qml;
  xdg.configFile."quickshell/desktop/LaptopOmniHost.qml".force = true; xdg.configFile."quickshell/desktop/LaptopOmniHost.qml".source = ./quickshell-configs/desktop/LaptopOmniHost.qml;
  xdg.configFile."quickshell/desktop/OSD.qml".force = true; xdg.configFile."quickshell/desktop/OSD.qml".source = ./quickshell-configs/desktop/OSD.qml;
  xdg.configFile."quickshell/desktop/NotificationOSD.qml".force = true; xdg.configFile."quickshell/desktop/NotificationOSD.qml".source = ./quickshell-configs/desktop/NotificationOSD.qml;
  xdg.configFile."quickshell/desktop/BrightnessOSD.qml".force = true; xdg.configFile."quickshell/desktop/BrightnessOSD.qml".source = ./quickshell-configs/desktop/BrightnessOSD.qml;
  xdg.configFile."quickshell/desktop/Bar.qml".force = true; xdg.configFile."quickshell/desktop/Bar.qml".source = ./quickshell-configs/desktop/Bar.qml;
  xdg.configFile."quickshell/desktop/Workspace.qml".force = true; xdg.configFile."quickshell/desktop/Workspace.qml".source = ./quickshell-configs/desktop/Workspace.qml;
  xdg.configFile."quickshell/desktop/Bloom.qml".force = true; xdg.configFile."quickshell/desktop/Bloom.qml".source = ./quickshell-configs/desktop/Bloom.qml;
  xdg.configFile."quickshell/desktop/Module.qml".force = true; xdg.configFile."quickshell/desktop/Module.qml".source = ./quickshell-configs/desktop/Module.qml;
  xdg.configFile."quickshell/desktop/Separator.qml".force = true; xdg.configFile."quickshell/desktop/Separator.qml".source = ./quickshell-configs/desktop/Separator.qml;
  xdg.configFile."quickshell/desktop/Bookmarks.qml".force = true; xdg.configFile."quickshell/desktop/Bookmarks.qml".source = ./quickshell-configs/desktop/Bookmarks.qml;
  xdg.configFile."quickshell/desktop/BatteryPopup.qml".force = true; xdg.configFile."quickshell/desktop/BatteryPopup.qml".source = ./quickshell-configs/desktop/BatteryPopup.qml;
  xdg.configFile."quickshell/desktop/ClipboardSearch.qml".force = true; xdg.configFile."quickshell/desktop/ClipboardSearch.qml".source = ./quickshell-configs/desktop/ClipboardSearch.qml;
  xdg.configFile."quickshell/desktop/AppScan.qml".force = true; xdg.configFile."quickshell/desktop/AppScan.qml".source = ./quickshell-configs/desktop/AppScan.qml;
  xdg.configFile."quickshell/desktop/CalendarPopup.qml".force = true; xdg.configFile."quickshell/desktop/CalendarPopup.qml".source = ./quickshell-configs/desktop/CalendarPopup.qml;
  xdg.configFile."quickshell/desktop/CalendarChevron.qml".force = true; xdg.configFile."quickshell/desktop/CalendarChevron.qml".source = ./quickshell-configs/desktop/CalendarChevron.qml;
  xdg.configFile."quickshell/desktop/CardWindow.qml".force = true; xdg.configFile."quickshell/desktop/CardWindow.qml".source = ./quickshell-configs/desktop/CardWindow.qml;
  xdg.configFile."quickshell/desktop/DisplayChip.qml".force = true; xdg.configFile."quickshell/desktop/DisplayChip.qml".source = ./quickshell-configs/desktop/DisplayChip.qml;
  xdg.configFile."quickshell/desktop/DisplaySlider.qml".force = true; xdg.configFile."quickshell/desktop/DisplaySlider.qml".source = ./quickshell-configs/desktop/DisplaySlider.qml;
  xdg.configFile."quickshell/desktop/WeatherPopup.qml".force = true; xdg.configFile."quickshell/desktop/WeatherPopup.qml".source = ./quickshell-configs/desktop/WeatherPopup.qml;
  xdg.configFile."quickshell/desktop/QuickAudioBody.qml".force = true; xdg.configFile."quickshell/desktop/QuickAudioBody.qml".source = ./quickshell-configs/desktop/QuickAudioBody.qml;
  xdg.configFile."quickshell/desktop/QuickBatteryBody.qml".force = true; xdg.configFile."quickshell/desktop/QuickBatteryBody.qml".source = ./quickshell-configs/desktop/QuickBatteryBody.qml;
  xdg.configFile."quickshell/desktop/QuickBluetoothBody.qml".force = true; xdg.configFile."quickshell/desktop/QuickBluetoothBody.qml".source = ./quickshell-configs/desktop/QuickBluetoothBody.qml;
  xdg.configFile."quickshell/desktop/QuickCalendarBody.qml".force = true; xdg.configFile."quickshell/desktop/QuickCalendarBody.qml".source = ./quickshell-configs/desktop/QuickCalendarBody.qml;
  xdg.configFile."quickshell/desktop/QuickCpuBody.qml".force = true; xdg.configFile."quickshell/desktop/QuickCpuBody.qml".source = ./quickshell-configs/desktop/QuickCpuBody.qml;
  xdg.configFile."quickshell/desktop/QuickPowerBody.qml".force = true; xdg.configFile."quickshell/desktop/QuickPowerBody.qml".source = ./quickshell-configs/desktop/QuickPowerBody.qml;
  xdg.configFile."quickshell/desktop/QuickSlider.qml".force = true; xdg.configFile."quickshell/desktop/QuickSlider.qml".source = ./quickshell-configs/desktop/QuickSlider.qml;
  xdg.configFile."quickshell/desktop/QuickWeatherBody.qml".force = true; xdg.configFile."quickshell/desktop/QuickWeatherBody.qml".source = ./quickshell-configs/desktop/QuickWeatherBody.qml;
  xdg.configFile."quickshell/desktop/QuickWifiBody.qml".force = true; xdg.configFile."quickshell/desktop/QuickWifiBody.qml".source = ./quickshell-configs/desktop/QuickWifiBody.qml;
  xdg.configFile."quickshell/desktop/QuickButton.qml".force = true; xdg.configFile."quickshell/desktop/QuickButton.qml".source = ./quickshell-configs/desktop/QuickButton.qml;
  xdg.configFile."quickshell/desktop/omni/Footer.qml".force = true; xdg.configFile."quickshell/desktop/omni/Footer.qml".source = ./quickshell-configs/desktop/omni/Footer.qml;
  xdg.configFile."quickshell/desktop/omni/HeaderBar.qml".force = true; xdg.configFile."quickshell/desktop/omni/HeaderBar.qml".source = ./quickshell-configs/desktop/omni/HeaderBar.qml;
  xdg.configFile."quickshell/desktop/omni/PreviewPane.qml".force = true; xdg.configFile."quickshell/desktop/omni/PreviewPane.qml".source = ./quickshell-configs/desktop/omni/PreviewPane.qml;
  xdg.configFile."quickshell/desktop/omni/QuickContainer.qml".force = true; xdg.configFile."quickshell/desktop/omni/QuickContainer.qml".source = ./quickshell-configs/desktop/omni/QuickContainer.qml;
  xdg.configFile."quickshell/desktop/omni/ResultList.qml".force = true; xdg.configFile."quickshell/desktop/omni/ResultList.qml".source = ./quickshell-configs/desktop/omni/ResultList.qml;
  xdg.configFile."quickshell/desktop/omni/SearchInput.qml".force = true; xdg.configFile."quickshell/desktop/omni/SearchInput.qml".source = ./quickshell-configs/desktop/omni/SearchInput.qml;
  xdg.configFile."quickshell/desktop/omni/Format.js".force = true; xdg.configFile."quickshell/desktop/omni/Format.js".source = ./quickshell-configs/desktop/omni/Format.js;
  xdg.configFile."quickshell/desktop/omni/Tiles.js".force = true; xdg.configFile."quickshell/desktop/omni/Tiles.js".source = ./quickshell-configs/desktop/omni/Tiles.js;
  xdg.configFile."quickshell/desktop/omni/EmojiGrid.qml".force = true; xdg.configFile."quickshell/desktop/omni/EmojiGrid.qml".source = ./quickshell-configs/desktop/omni/EmojiGrid.qml;

  # systemd env so Quickshell finds the Wayland display
  systemd.user.services.quickshell-desktop = {
    Unit.Description = "Quickshell desktop shell";
    Service = {
      Environment = [
        "WAYLAND_DISPLAY=wayland-1"
        "QML_IMPORT_PATH=${pkgs.qt6.qt5compat}/lib/qt-6/qml"
      ];
      ExecStart = "${pkgs.quickshell}/bin/qs -n -c desktop";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}