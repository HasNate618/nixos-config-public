{ ... }: {
  # cava audio visualizer config
  xdg.configFile."cava/config" = {
    force = true;
    text = ''
## Configuration file for CAVA.

[general]
; live-config = 0
; mode = normal
; framerate = 60
; autosens = 1
; overshoot = 20
; sensitivity = 100
; bars = 0
; bar_width = 2
; bar_spacing = 1
; center_align = 1
; max_height = 100
; lower_cutoff_freq = 50
; higher_cutoff_freq = 10000
; sleep_timer = 0

[input]
; method = pulse
; source = auto

[output]
; method = noncurses
; orientation = bottom
; channels = stereo
; mono_option = average
; reverse = 0
; xaxis = none
; synchronized_sync = 0

[color]
; background = default
; foreground = default
; gradient = 0
theme = 'matugen'

[smoothing]
; noise_reduction = 77

[eq]
; 1 = 1
; 2 = 1
; 3 = 1
; 4 = 1
; 5 = 1
    '';
  };
}
