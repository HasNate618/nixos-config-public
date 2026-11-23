#!/bin/sh
# Push colours to running foot terminals via OSC escape sequences, and keep
# colors.ini consistent for terminals started later.
#
# Called by skwd-wall after regenerating colors.ini (matugen pipeline) and
# directly by the focus-mode scripts. Two modes:
#
#   focus mode ON  (guard ~/.cache/focus-mode exists):
#     * colours come from the ACTIVE focus scheme, not from matugen;
#     * alpha is forced to 1.0 and pushed via OSC 11 'rgba:.../ffff' —
#       the only way to change foot transparency at runtime (foot does not
#       re-read config; OSC 11 with an explicit alpha swaps the compositor
#       surface alpha live);
#     * colors.ini is rewritten with the same values so a terminal opened
#       *during* focus matches the running ones.
#
#   focus mode OFF:
#     * colours and alpha come from colors.ini (matugen output). The alpha
#       is pushed explicitly (not bare #RRGGBB) so terminals whose
#       configured alpha was loaded during a focus session (1.0) revert
#       to the translucent value too.
#
# SIGUSR1 does NOT work for this: it only toggles foot's colour theme.
set -u

COLORS_INI="$HOME/.config/foot/colors.ini"
FOCUS_GUARD="$HOME/.cache/focus-mode"
SCHEMES="$HOME/.config/focus-mode/schemes"
ACTIVE_FILE="$HOME/.config/focus-mode/active"

mode=focus
[ -f "$FOCUS_GUARD" ] || mode=normal

background=""; foreground=""; sel_bg=""; sel_fg=""; alpha=""
i=0
while [ "$i" -lt 8 ]; do
    eval "regular$i=''"
    eval "bright$i=''"
    i=$((i+1))
done

if [ "$mode" = focus ]; then
    slug=$(cat "$ACTIVE_FILE" 2>/dev/null || true)
    [ -n "$slug" ] || slug=kanagawa-dragon
    scheme="$SCHEMES/$slug.conf"
    if [ -f "$scheme" ]; then
        get() { sed -n "s/^$1=//p" "$scheme" | head -1 | tr -d '[:space:]#'; }
        background=$(get background)
        foreground=$(get foreground)
        sel_bg=$(get selection_background)
        sel_fg=$(get selection_foreground)
        i=0
        while [ "$i" -lt 8 ]; do
            eval "regular$i=\$(get regular$i)"
            eval "bright$i=\$(get bright$i)"
            i=$((i+1))
        done
        alpha=1.000000
    fi
    # A missing/unreadable scheme falls through to colors.ini below.
    [ -n "$background" ] || mode=normal
fi

if [ "$mode" = normal ]; then
    [ -f "$COLORS_INI" ] || exit 0
    background=$(sed -n 's/^background=//p' "$COLORS_INI")
    foreground=$(sed -n 's/^foreground=//p' "$COLORS_INI")
    sel_bg=$(sed -n 's/^selection-background=//p' "$COLORS_INI")
    sel_fg=$(sed -n 's/^selection-foreground=//p' "$COLORS_INI")
    alpha=$(sed -n 's/^alpha=//p' "$COLORS_INI")
    i=0
    while [ "$i" -lt 8 ]; do
        eval "regular$i=\$(sed -n \"s/^regular${i}=//p\" \"$COLORS_INI\")"
        eval "bright$i=\$(sed -n \"s/^bright${i}=//p\" \"$COLORS_INI\")"
        i=$((i+1))
    done
fi

background=${background:-000000}
foreground=${foreground:-c5c9c5}
alpha=${alpha:-0.200000}

# alpha (0.0-1.0) → 16-bit hex for OSC 11 'rgba:.../XXXX' (0.2 → 0x3333)
alpha_hex=$(awk -v a="$alpha" 'BEGIN { v = a * 65535; if (v > 65535) v = 65535; if (v < 0) v = 0; printf "%04x", int(v + 0.5) }')
[ -n "$alpha_hex" ] || alpha_hex=ffff

# ── focus: rewrite colors.ini so terminals opened now match running ones ──
if [ "$mode" = focus ]; then
    tmp="${COLORS_INI}.tmp.$$"
    {
        printf '# Focus-mode scheme (matugen output suspended while focus mode is on)\n'
        printf '[colors-dark]\n'
        printf 'alpha=1.000000\n'
        printf 'blur=yes\n'
        printf 'background=%s\n' "$background"
        printf 'foreground=%s\n' "$foreground"
        [ -n "$sel_fg" ] && printf 'selection-foreground=%s\n' "$sel_fg"
        [ -n "$sel_bg" ] && printf 'selection-background=%s\n' "$sel_bg"
        printf '\n'
        i=0
        while [ "$i" -lt 8 ]; do
            eval "c=\$regular$i"
            printf 'regular%s=%s\n' "$i" "${c:-$background}"
            i=$((i+1))
        done
        printf '\n'
        i=0
        while [ "$i" -lt 8 ]; do
            eval "c=\$bright$i"
            printf 'bright%s=%s\n' "$i" "${c:-$foreground}"
            i=$((i+1))
        done
    } > "$tmp" 2>/dev/null && mv "$tmp" "$COLORS_INI" || rm -f "$tmp"
fi

# ── build OSC payload ──
# OSC 11 sets the default background colour AND alpha: an alpha-less OSC 11
# restores the configured alpha, an explicit one sets it (foot switches the
# compositor surface between ARGB/XRGB live).
osc_bg=$(printf '\033]11;rgba:%s/%s/%s/%s\007' \
    "$(echo "$background" | cut -c1-2)" "$(echo "$background" | cut -c3-4)" \
    "$(echo "$background" | cut -c5-6)" "$alpha_hex")
osc_fg=$(printf '\033]10;#%s\007' "$foreground")

osc_palette=""
i=0
while [ "$i" -lt 8 ]; do
    eval "c=\$regular$i"
    osc_palette="${osc_palette}$(printf '\033]4;%s;#%s\007' "$i" "${c:-000000}")"
    i=$((i+1))
done
i=0
while [ "$i" -lt 8 ]; do
    eval "c=\$bright$i"
    osc_palette="${osc_palette}$(printf '\033]4;%s;#%s\007' "$((i+8))" "${c:-000000}")"
    i=$((i+1))
done

osc="${osc_bg}${osc_fg}${osc_palette}"

# Send to all user-owned PTYs and TTYs — harmless to non-foot terminals
for tty in /dev/pts/[0-9]* /dev/tty[0-9]*; do
    [ -c "$tty" ] || continue
    [ "$(stat -c '%u' "$tty" 2>/dev/null)" = "$(id -u)" ] || continue
    printf '%s' "$osc" > "$tty" 2>/dev/null || true
done
