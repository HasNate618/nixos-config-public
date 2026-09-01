#!/bin/sh
# reload-zen.sh — updates Zen transparency pref from matugen-generated CSS
echo "$(date): called" >> /tmp/zen-reload.log

ZEN_PROFILE="/home/nate/.config/zen/7khcdo47.Default (release)"
CSS_FILE="$ZEN_PROFILE/chrome/zen-themes/matugen-transparency/chrome.css"
PREFS_FILE="$ZEN_PROFILE/prefs.js"
USER_JS="$ZEN_PROFILE/user.js"

[ -f "$CSS_FILE" ] || exit 0

# Extract the transparency color from the CSS (no scaling — all apps use
# the same colors.surface now)
COLOR=$(grep -m1 -F -- '--zen-transparency-color' "$CSS_FILE" | sed 's/.*: *\([^;]*\);.*/\1/')

[ -z "$COLOR" ] && exit 0

# Update prefs.js and user.js
for pf in "$PREFS_FILE" "$USER_JS"; do
  [ -f "$pf" ] || continue
  if grep -q 'mod.sameerasw.zen_transparency_color' "$pf" 2>/dev/null; then
    sed -i "s|user_pref(\"mod.sameerasw.zen_transparency_color\", \"[^\"]*\");|user_pref(\"mod.sameerasw.zen_transparency_color\", \"$COLOR\");|" "$pf"
  else
    echo "user_pref(\"mod.sameerasw.zen_transparency_color\", \"$COLOR\");" >> "$pf"
  fi
  for pref in 'widget.transparent-windows,true' 'zen.widget.linux.transparency,true' 'zen.theme.gradient.show-custom-colors,true'; do
    NAME="${pref%,*}"
    VAL="${pref#*,}"
    if grep -q "user_pref(\"$NAME\"" "$pf" 2>/dev/null; then
      sed -i "s|user_pref(\"$NAME\", [^)]*);|user_pref(\"$NAME\", $VAL);|" "$pf"
    else
      echo "user_pref(\"$NAME\", $VAL);" >> "$pf"
    fi
  done
done

echo "$(date): done, COLOR=$COLOR" >> /tmp/zen-reload.log
