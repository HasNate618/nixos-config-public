{ config, pkgs, ... }: {
  services.keyd = {
    enable = true;
    keyboards = {
      corne = {
        ids = [ "1d50:615e" ];
        settings.main = {
          capslock = "overload(control, esc)";
          mouse2 = "leftmeta";
        };
        settings.control = {
          capslock = "capslock";
        };
      };
      default = {
        ids = [ "*" "m:3554:fc03:f6faaf7b" ];
        settings.main = {
          capslock = "overload(control, esc)";
          mouse2 = "leftmeta";
          rightalt = "overload(arrows, f13)";
        };
        settings.control = {
          capslock = "capslock";
        };
        settings.arrows = {
          h = "left";
          j = "down";
          k = "up";
          l = "right";
          u = "home";
          i = "pagedown";
          o = "pageup";
          p = "end";
        };
      };
    };
  };
}
