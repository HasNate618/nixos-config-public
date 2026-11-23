# Hyprlock overlay: random-character password display.
#
# Adds a "@rand:<font>:<charset>" mode to dots_text_format: instead of
# stamping one static glyph per typed character, the whole visible password
# is re-rolled into a fresh random string from <charset> on every length
# change and rendered centered in the field. <font> is a fontconfig family
# (empty = the input field's font_family). See the patch for details.
self: super: {
  hyprlock = super.hyprlock.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./hyprlock-random-dots.patch ];
  });
}
