#!/bin/sh
# Push colors to running foot terminals via OSC escape sequences
# Called by skwd-wall after regenerating colors.ini
#
# Foot's SIGUSR1 only toggles dark/light themes — it does NOT re-read
# config. Use OSC 4/10/11 to push colors to running terminals at runtime.

COLORS_INI="/home/nate/.config/foot/colors.ini"
[ -f "$COLORS_INI" ] || exit 0

# Extract color values from colors.ini (POSIX-compatible)
background=$(sed -n 's/^background=//p' "$COLORS_INI")
foreground=$(sed -n 's/^foreground=//p' "$COLORS_INI")
for i in 0 1 2 3 4 5 6 7; do
  eval "regular$i=$(sed -n "s/^regular${i}=//p" "$COLORS_INI")"
  eval "bright$i=$(sed -n "s/^bright${i}=//p" "$COLORS_INI")"
done

# Build OSC sequences (BEL-terminated)
background="${background:-000000}"
foreground="${foreground:-ffffff}"

OSC_BG=$(printf '\033]11;%s\007' "#${background}")
OSC_FG=$(printf '\033]10;%s\007' "#${foreground}")

OSC_PALETTE=""
for i in 0 1 2 3 4 5 6 7; do
  eval "c=\$regular${i}"
  c="${c:-000000}"
  OSC_PALETTE="${OSC_PALETTE}$(printf '\033]4;%s;%s\007' "$i" "#${c}")"
done
for i in 0 1 2 3 4 5 6 7; do
  eval "c=\$bright${i}"
  c="${c:-000000}"
  OSC_PALETTE="${OSC_PALETTE}$(printf '\033]4;%s;%s\007' "$((i+8))" "#${c}")"
done

OSC="${OSC_BG}${OSC_FG}${OSC_PALETTE}"

# Send to all user-owned PTYs and TTYs — harmless to non-foot terminals
for tty in /dev/pts/[0-9]* /dev/tty[0-9]*; do
  [ -c "$tty" ] || continue
  [ "$(stat -c '%u' "$tty" 2>/dev/null)" = "$(id -u)" ] || continue
  printf '%b' "$OSC" > "$tty" 2>/dev/null || true
done
