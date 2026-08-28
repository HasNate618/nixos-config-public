{ config, lib, pkgs, hyprland-preview-share-picker, ... }: {
  # Hyprland compositor
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # GPU drivers for Intel Iris Xe (ROG Flow X16)
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  # Display manager
  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
    };
    autoLogin = {
      enable = true;
      user = "nate";
    };
  };

  # Environment variables for Hyprland
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    WLR_NO_HARDWARE_CURSORS = "1";
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_DESKTOP = "Hyprland";
    XDG_COLOR_SCHEME = "dark";
    GTK_THEME = "Adwaita-dark";
  };

  # Fonts
  fonts.packages = with pkgs; [
    jetbrains-mono
    nerd-fonts.jetbrains-mono
    noto-fonts-color-emoji
    noto-fonts
    terminus_font
  ];

  environment.systemPackages = with pkgs; [
    hyprland-preview-share-picker
    gsettings-desktop-schemas
    xdg-desktop-portal-termfilechooser
  ];

  # Audio
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    extraConfig.pipewire."92-desktop-audio" = {
      "context.objects" = [
        {
          factory = "adapter";
          args = {
            "factory.name"     = "support.null-audio-sink";
            "node.name"        = "desktop-audio";
            "node.description" = "Desktop Audio";
            "media.class"      = "Audio/Sink";
            "audio.position"   = "FL,FR";
          };
        }
      ];
    };
  };

  # Force Intel HDA to HDMI/DP profile for USB-C monitor audio
  systemd.user.services.wireplumber-hdmi-fix = {
    description = "Switch Intel HDA to HDMI audio profile";
    after = [ "wireplumber.service" ];
    wants = [ "wireplumber.service" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.writeShellScript "hdmi-profile" ''
        sleep 3
        # Find Intel HDA card ID (first "Built-in Audio" device, not NVIDIA AD107)
        CARD=$(wpctl status 2>/dev/null | awk "/Devices:/{found=1} found && /Built-in Audio.*alsa/{print \$2; exit}")
        if [ -n "$CARD" ]; then
          wpctl set-profile "$CARD" 4 2>/dev/null || true
          # Set HDMI 3 as default sink
          HDMISINK=$(wpctl status 2>/dev/null | grep "HDMI 3" | awk '{print $2}')
          [ -n "$HDMISINK" ] && wpctl set-default "$HDMISINK" 2>/dev/null || true
        fi
      ''}";
    };
  };
  services.pipewire.wireplumber.extraConfig."11-hdmi-audio" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "device.name" = "alsa_card.pci-0000_00_1f.3"; }
        ];
        actions = { "update-props" = {
          "api.acp.auto-profile" = true;
          "api.acp.auto-port" = true;
        }; };
      }
    ];
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # XDG portal for screensharing
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [ xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-desktop-portal-termfilechooser ];
    config = {
      common = {
        default = [ "hyprland" "gtk" ];
        "org.freedesktop.impl.portal.Settings" = "gtk";
        "org.freedesktop.impl.portal.FileChooser" = "termfilechooser";
      };
    };
  };

  # Polkit for authentication dialogs
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  security.polkit.enable = true;

  # Allow suspend without password — needed by hypridle's suspend listener
  # since the display is already locked when suspend triggers
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.login1.suspend" &&
          subject.user == "nate") {
        return polkit.Result.YES;
      }
    });
  '';
}
