{ config, pkgs, ... }: {
  services.keyd = {
    enable = true;
    keyboards = {
      corne = {
        ids = [ "1d50:615e" ];
        settings.main = {
          capslock = "overload(control, esc)";
          mouse2 = "layer(meta)";
        };
        settings.control = {
          capslock = "capslock";
        };
      };
      default = {
        ids = [ "*" ];
        settings.main = {
          capslock = "overload(control, esc)";
          mouse2 = "layer(meta)";
          rightalt = "layer(arrows)";
        };
        settings.control = {
          capslock = "capslock";
        };
        settings.arrows = {
          h = "left";
          j = "down";
          k = "up";
          l = "right";
          y = "home";
          u = "end";
          i = "pgup";
          o = "pgdn";
        };
      };
    };
  };
}
