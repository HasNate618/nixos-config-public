{ ... }: {
  # ROG Control Center config for ASUS laptop
  xdg.configFile."rog/rog-control-center.cfg" = {
    force = true;
    text = ''
      (
          run_in_background: false,
          startup_in_background: false,
          enable_tray_icon: true,
          ac_command: "",
          bat_command: "",
          dark_mode: true,
          start_fullscreen: false,
          fullscreen_width: 1920,
          fullscreen_height: 1080,
          notifications: (
              enabled: true,
              receive_notify_gfx: true,
              receive_notify_gfx_status: true,
          ),
      )
    '';
  };
}
