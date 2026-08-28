#!/usr/bin/env bash
# Patch MonoThemeDark's gtk.css with matugen content area background
set -e

GTK_CSS="$HOME/.config/gtk-4.0/gtk.css"
THEME_CSS="$HOME/.themes/MonoThemeDark/gtk-4.0/gtk.css"

[ -f "$GTK_CSS" ] || exit 0
[ -f "$THEME_CSS" ] || exit 0

# Extract RGB values from matugen-generated CSS (matugen_surface line)
BG_RGB=$(grep -m1 'matugen_surface rgba' "$GTK_CSS" | sed 's/.*rgba(\([^)]*\)).*/\1/')
[ -z "$BG_RGB" ] && exit 0

R=$(echo "$BG_RGB" | cut -d, -f1 | tr -d ' ')
G=$(echo "$BG_RGB" | cut -d, -f2 | tr -d ' ')
B=$(echo "$BG_RGB" | cut -d, -f3 | tr -d ' ')

[ -z "$R" ] || [ -z "$G" ] || [ -z "$B" ] && exit 0

# Find the matugen block at the end and update it
if grep -q 'Matugen: content area background' "$THEME_CSS"; then
    # Update existing line (match any alpha value)
    sed -i "s/@define-color theme_base_color rgba([0-9]*, [0-9]*, [0-9]*, [0-9.]*);/@define-color theme_base_color rgba($R, $G, $B, 0.20);/" "$THEME_CSS"
else
    # Append new block
    echo "" >> "$THEME_CSS"
    echo "/* Matugen: content area background (20% opacity) */" >> "$THEME_CSS"
    echo "@define-color theme_base_color rgba($R, $G, $B, 0.20);" >> "$THEME_CSS"
fi
