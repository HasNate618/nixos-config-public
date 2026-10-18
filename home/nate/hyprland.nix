{ config, pkgs, ... }:

let
  # Set matugen-themed hyprland borders from quickshell colors.toml
  hyprland-border-theme = pkgs.writeShellScriptBin "hyprland-border-theme" ''
    CACHE_FILE="$HOME/.cache/skwd-wall/hyprland-border-color"
    COLORS_FILE="$HOME/.config/quickshell/colors.toml"
    ACTIVE="#adccd5"
    INACTIVE="#112426"
    if [ -f "$CACHE_FILE" ]; then
      AC=$(head -1 "$CACHE_FILE" | tr -d '[:space:]')
      [ -n "$AC" ] && ACTIVE="$AC"
    elif [ -f "$COLORS_FILE" ]; then
      _get() { sed -n "s/^\$1 *= *\"\(.*\)\"/\1/p" "$COLORS_FILE" | head -1; }
      AC="$(_get accent)" && [ -n "$AC" ] && ACTIVE="$AC"
      BG="$(_get background)" && [ -n "$BG" ] && INACTIVE="$BG"
    fi
    _darken() {
      /etc/profiles/per-user/nate/bin/python3 -c "
    h = '$1'.lstrip('#')
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    factor = 0.35
    r = int(r * factor)
    g = int(g * factor)
    b = int(b * factor)
    print(f'#{r:02x}{g:02x}{b:02x}')
    "
    }
    COMPUTED_INACTIVE="$(_darken "$ACTIVE")"
    [ "$COMPUTED_INACTIVE" = "$ACTIVE" ] || [ -z "$COMPUTED_INACTIVE" ] && COMPUTED_INACTIVE="$INACTIVE"
    _hex_to_rgba() {
      local hex="$1"
      hex=''${hex#\#}
      echo "rgba(''${hex}ee)"
    }
    ACTIVE_RGBA="$(_hex_to_rgba "$ACTIVE")"
    INACTIVE_RGBA="rgba($(echo "$COMPUTED_INACTIVE" | sed "s/^#//")01)"

    # Group borders — tertiary color, darkened for inactive
    GROUP_ACTIVE="#e7bfa0"
    GROUP_INACTIVE="#3e2b19"
    GROUP_FILE="$HOME/.cache/skwd-wall/hyprland-group-border-color"
    if [ -f "$GROUP_FILE" ]; then
      GC=$(head -1 "$GROUP_FILE" | tr -d '[:space:]')
      [ -n "$GC" ] && GROUP_ACTIVE="$GC"
    elif [ -f "$COLORS_FILE" ]; then
      GC="$(_get color1)" && [ -n "$GC" ] && GROUP_ACTIVE="$GC"
    fi
    GROUP_COMPUTED_INACTIVE="$(_darken "$GROUP_ACTIVE")"
    [ "$GROUP_COMPUTED_INACTIVE" = "$GROUP_ACTIVE" ] || [ -z "$GROUP_COMPUTED_INACTIVE" ] && GROUP_COMPUTED_INACTIVE="$GROUP_INACTIVE"
    GROUP_ACTIVE_RGBA="$(_hex_to_rgba "$GROUP_ACTIVE")"
    GROUP_INACTIVE_RGBA="rgba($(echo "$GROUP_COMPUTED_INACTIVE" | sed "s/^#//")01)"

    # Always resolve the live Hyprland socket — the inherited HYPRLAND_INSTANCE_SIGNATURE
    # (e.g. from skwd-daemon's env) may point to a stale/crashed session. ss shows the
    # socket actually listening; fall back to ls -1t only if ss finds nothing.
    # Skip border theme in focus mode (borders are disabled)
    [ -f "$HOME/.cache/focus-mode" ] && exit 0

    _sock=$(ss -xlp 2>/dev/null | grep -o "/run/user/1000/hypr/[^ ]*\.socket\.sock" | head -1)
    _sig=""
    [ -n "$_sock" ] && _sig="$(basename "$(dirname "$_sock")")"
    [ -z "$_sig" ] && _sig=$(ls -1t /run/user/1000/hypr 2>/dev/null | head -1)
    export HYPRLAND_INSTANCE_SIGNATURE="$_sig"
    if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
      hyprctl eval "hl.config({[\"general.col.active_border\"]=\"$ACTIVE_RGBA\",[\"general.col.inactive_border\"]=\"$INACTIVE_RGBA\",[\"general.border_size\"]=1,[\"decoration.rounding\"]=0,[\"group.col.border_active\"]=\"$GROUP_ACTIVE_RGBA\",[\"group.col.border_inactive\"]=\"$GROUP_INACTIVE_RGBA\"})"
    fi
  '';
  # TUI launcher — spawns foot with title tag, focuses if already open.
  # Float/center handled by Lua windowrules matching title.
  launch-tui = pkgs.writeShellScriptBin "launch-tui" ''
    NAME="$1"; shift
    TITLE="tui-''${NAME}"
    WIN=$(hyprctl clients -j 2>/dev/null | jq -r ".[] | select(.title == \"$TITLE\") | .address" 2>/dev/null | head -1)
    if [ -n "$WIN" ]; then
      hyprctl dispatch focuswindow "address:$WIN" 2>/dev/null
      exit 0
    fi
    exec foot --title="$TITLE" -e "$@"
  '';

  audio-switch = pkgs.writeShellScriptBin "hypr-audio-switch" ''
    set -euo pipefail
    SINKS=$(pactl -f json list sinks | jq '[.[] | select((.ports | length == 0) or ([.ports[]? | .availability != "not available"] | any))]')
    COUNT=$(echo "$SINKS" | jq 'length')
    [ "$COUNT" -eq 0 ] && { notify-send "No audio devices found"; exit 0; }
    CURRENT=$(pactl get-default-sink)
    IDX=$(echo "$SINKS" | jq -r --arg name "$CURRENT" 'map(.name) | index($name)')
    [ "$IDX" = "null" ] && IDX=-1
    NEXT=$(( (IDX + 1) % COUNT ))
    NEXT_DESC=$(echo "$SINKS" | jq -r ".[$NEXT].description")
    NEXT_ID=$(echo "$SINKS" | jq -r ".[$NEXT].properties.\"object.id\"")
    wpctl set-default "$NEXT_ID"
    notify-send -u low "Audio" "$NEXT_DESC"
  '';

  nightlight-toggle = pkgs.writeShellScriptBin "hypr-nightlight-toggle" ''
    ON_TEMP=4000; OFF_TEMP=6000
    pgrep -x hyprsunset >/dev/null || { hyprsunset &>/dev/null & sleep 0.5; }
    CURRENT=$(hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' || echo "$OFF_TEMP")
    if [ "$CURRENT" = "$OFF_TEMP" ]; then
      hyprctl hyprsunset temperature "$ON_TEMP" && notify-send -u low "Nightlight on (''${ON_TEMP}K)"
    else
      hyprctl hyprsunset temperature "$OFF_TEMP" && notify-send -u low "Nightlight off"
    fi
  '';

  idle-toggle = pkgs.writeShellScriptBin "hypr-idle-toggle" ''
    if systemctl --user is-active hypridle >/dev/null 2>&1; then
      systemctl --user stop hypridle
      # hypridle owns the wake path (on-resume DPMS + kbd restore); with it stopped the
      # still-locked hyprlock would keep the desk dark — restore display + kbd here.
      # Resolve the live socket: ssh/agent contexts may carry no (or a stale) signature.
      _sock=$(ss -xlp 2>/dev/null | grep -o "/run/user/1000/hypr/[^ ]*\.socket\.sock" | head -1)
      _sig=""
      [ -n "$_sock" ] && _sig="$(basename "$(dirname "$_sock")")"
      [ -z "$_sig" ] && _sig=$(ls -1t /run/user/1000/hypr 2>/dev/null | head -1)
      [ -n "$_sig" ] && HYPRLAND_INSTANCE_SIGNATURE="$_sig" hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'
      "$HOME/.local/bin/kbd-save-restore" restore
      notify-send -u low "Idle lock disabled"
    else
      systemctl --user start hypridle
      notify-send -u low "Idle lock enabled"
    fi
  '';

  gaps-toggle = pkgs.writeShellScriptBin "hypr-gaps-toggle" ''
    # Always resolve the live Hyprland socket — the inherited HYPRLAND_INSTANCE_SIGNATURE
    # (e.g. from skwd-daemon's env) may point to a stale/crashed session. ss shows the
    # socket actually listening; fall back to ls -1t only if ss finds nothing.

    _sock=$(ss -xlp 2>/dev/null | grep -o "/run/user/1000/hypr/[^ ]*\.socket\.sock" | head -1)
    _sig=""
    [ -n "$_sock" ] && _sig="$(basename "$(dirname "$_sock")")"
    [ -z "$_sig" ] && _sig=$(ls -1t /run/user/1000/hypr 2>/dev/null | head -1)
    export HYPRLAND_INSTANCE_SIGNATURE="$_sig"
    OUT=14; IN=8
    CUR_OUT=$(hyprctl getoption general:gaps_out -j | jq -r '.css' | awk '{print $1}')
    [ -z "$CUR_OUT" ] && CUR_OUT=0
    if [ "$CUR_OUT" -eq 0 ]; then
hyprctl eval "hl.config({[\"general.gaps_out\"]=$OUT,[\"general.gaps_in\"]=$IN,[\"general.border_size\"]=1,[\"decoration.rounding\"]=0,[\"decoration.shadow.enabled\"]=true})" && hyprland-border-theme
    else
hyprctl eval "hl.config({[\"general.gaps_out\"]=0,[\"general.gaps_in\"]=0,[\"general.border_size\"]=0,[\"decoration.rounding\"]=0,[\"decoration.shadow.enabled\"]=false,[\"general.col.inactive_border\"]=\"rgba(00000000)\"})"
    fi
  '';
  pin-toggle = pkgs.writeShellScriptBin "hypr-pin-toggle" ''
    INFO=$(hyprctl activewindow -j | jq '{pinned, floating}')
    PINNED=$(echo "$INFO" | jq -r '.pinned')
    FLOATING=$(echo "$INFO" | jq -r '.floating')
    if [ "$PINNED" = "true" ]; then
      # Pinned → unpin, unfloat, restore to tiled
      hyprctl eval 'hl.dispatch(hl.dsp.window.pin())'
      hyprctl eval 'hl.dispatch(hl.dsp.window.float({ action = "set", value = false }))'
    elif [ "$FLOATING" = "true" ]; then
      # Floating but not pinned → just pin
      hyprctl eval 'hl.dispatch(hl.dsp.window.pin())'
    else
      # Tiled → float and pin
      hyprctl eval 'hl.dispatch(hl.dsp.window.float({ action = "set", value = true }))'
      hyprctl eval 'hl.dispatch(hl.dsp.window.pin())'
    fi
  '';
  monitor-scaling = pkgs.writeShellScriptBin "hypr-monitor-scaling" ''
    INFO=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true)')
    MONITOR=$(echo "$INFO" | jq -r '.name'); SCALE=$(echo "$INFO" | jq -r '.scale')
    W=$(echo "$INFO" | jq -r '.width'); H=$(echo "$INFO" | jq -r '.height')
    RR=$(echo "$INFO" | jq -r '.refreshRate')
    SCALES=(1 1.25 1.6 2 3 4)
    BEST=999; IDX=0
    for i in "''${!SCALES[@]}"; do
      d=$(awk "BEGIN{print ($SCALE - ''${SCALES[$i]})^2}")
      [ "$(awk "BEGIN{print ($d < $BEST)}")" = 1 ] && { BEST=$d; IDX=$i; }
    done
    NEW=$(( (IDX + 1) % ''${#SCALES[@]} ))
    hyprctl keyword monitor "$MONITOR,''${W}x''${H}@''${RR},auto,''${SCALES[$NEW]}"
    notify-send -u low "Display scaling: ''${SCALES[$NEW]}x"
  '';

  monitor-internal-toggle = pkgs.writeShellScriptBin "hypr-monitor-internal-toggle" ''
    INTERNAL=$(hyprctl monitors -j | jq -r '.[] | select(.name | contains("eDP")).name' | head -n1)
    [ -z "$INTERNAL" ] && exit 0
    DISABLED=$(hyprctl monitors -j | jq -r --arg m "$INTERNAL" '.[] | select(.name == $m) | .disabled')
    EXTERNAL=$(hyprctl monitors -j | jq -r '[.[] | select(.name | contains("eDP") | not) | select(.disabled == false)] | length')
    if [ "$DISABLED" = "true" ]; then
      MODE=$(hyprctl monitors -j | jq -r '.[] | select(.name == "$INTERNAL") | .mode' 2>/dev/null || echo "2560x1600@240")
      hyprctl keyword monitor "$INTERNAL,$MODE,-1280x0,1.25"
      notify-send -u low "Laptop display enabled"
    elif [ "$EXTERNAL" -eq 0 ]; then
      notify-send -u low "Cannot disable the only active display"
    else
      hyprctl keyword monitor "$INTERNAL,disable"
      notify-send -u low "Laptop display disabled"
    fi
  '';

  monitor-auto-layout = pkgs.writeShellScriptBin "hypr-monitor-auto-layout" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    discover_sig() {
      HYPRLAND_INSTANCE_SIGNATURE=""
      for d in /run/user/1000/hypr/*/; do
        s=$(basename "$d" 2>/dev/null) || continue
        if "$HYPRCTL" --instance "$s" monitors -j >/dev/null 2>&1; then
          HYPRLAND_INSTANCE_SIGNATURE=$s; break
        fi
      done
      if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
        export HYPRLAND_INSTANCE_SIGNATURE
      fi
    }
    discover_sig
    # No live compositor (boot or rebuild before the session is up): the
    # one-shot rebuild unit must skip cleanly (exit 0); the --listen daemon
    # exits 1 so systemd retries until Hyprland exists. Connect-test above
    # so a stale sig dir is never picked.
    if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
      case " $* " in
        *" --listen "*) exit 1 ;;
        *) exit 0 ;;
      esac
    fi

    # Get laptop (eDP) monitor name
    edp_name() {
      "$HYPRCTL" monitors -j | "$JQ" -r '.[] | select(.name | startswith("eDP")) | .name' | head -n1
    }

    # Get first enabled external monitor (not eDP)
    ext_name() {
      local edp="$1"
      "$HYPRCTL" monitors -j | "$JQ" -r --arg e "$edp" '[.[] | select(.disabled == false) | select(.name != $e)] | .[0].name // empty'
    }

    # Calculate laptop logical width accounting for transform AND scale
    # Transform 0,2 = landscape: use width/scale; Transform 1,3 = portrait: use height/scale
    calc_lw() {
      local edp="$1"
      "$HYPRCTL" monitors -j | "$JQ" -r --arg n "$edp" \
        '.[] | select(.name == $n) |
         (if (.transform // 0) == 1 or (.transform // 0) == 3
          then (.height / (.scale // 1))
          else (.width / (.scale // 1))
          end) | floor'
    }

    refresh_shell() {
      rm -rf "$HOME/.cache/quickshell/qmlcache" 2>/dev/null || true
      systemctl --user restart quickshell-desktop 2>/dev/null || true
    }

    refresh_hypr_visuals() {
      "$HYPRCTL" eval 'hl.layer_rule({match = {namespace = "omarchy-menu"}, blur = true})'
      "$HYPRCTL" reload
      sleep 0.6
    }

    reapply_wallpaper() {
      # skwd-wall v2 daemon owns per-output rendering; ask it to re-apply the
      # current wallpaper on every live output after the layout changed
      # (replaces the v1 daemon.sock RPC + manual skwd-paper-still spawns).
      local wall m
      wall=$("$JQ" -r '.path // empty' "$HOME/.cache/skwd-wall-v2/last-wallpaper.json" 2>/dev/null || true)
      [ -z "$wall" ] || [ ! -f "$wall" ] && return 0
      while IFS= read -r m; do
        [ -z "$m" ] && continue
        skwd-helm apply "$wall" -o "$m" 2>/dev/null || true
      done < <("$HYPRCTL" monitors -j | "$JQ" -r '.[] | select(.disabled == false) | .name')
    }

    apply_layout() {
      # Find external monitor (works whether eDP is enabled or disabled)
      local edp; edp="$(edp_name)"
      local ext; ext="$(ext_name "${edp:-}")"

      if [ -n "$ext" ]; then
        # External connected: disable laptop, use external only
        if [ -n "$edp" ]; then
          "$HYPRCTL" eval "hl.monitor({ output = \"$edp\", mode = \"disabled\" })" >/dev/null
        fi
        "$HYPRCTL" eval "hl.monitor({ output = \"$ext\", mode = \"3840x2160@120\", position = \"0x0\", scale = 1.25 })" >/dev/null
      elif [ -n "$edp" ]; then
        # Laptop only: restore eDP
        local tr; tr=$("$HYPRCTL" monitors -j | "$JQ" -r --arg n "$edp" \
          '.[] | select(.name == $n) | .transform // 0')
        local edp_mode; edp_mode=$("$HYPRCTL" monitors -j | "$JQ" -r --arg n "$edp" \
          '.[] | select(.name == $n) | "\(.width)x\(.height)@\(.refreshRate | floor)"')
        [ -z "$edp_mode" ] && edp_mode="2560x1600@240"
        "$HYPRCTL" eval "hl.monitor({ output = \"$edp\", mode = \"$edp_mode\", position = \"0x0\", scale = 1.25, transform = $tr })" >/dev/null
      fi
      # Reapply wallpaper after layout change (Hyprland resets to default otherwise)
      sleep 0.5
      reapply_wallpaper
    }

    handle() {
      case "$1" in
        monitoraddedv2*|monitorremovedv2*)
          # Longer delay on remove to let Hyprland clean up the monitor list
          case "$1" in
            monitorremovedv2*) sleep 1.5 ;;
            *) sleep 0.4 ;;
          esac
          apply_layout
          ;;
      esac
    }

    if [ "''${1:-}" = "--listen" ]; then
      discover_sig
      sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
      ${pkgs.socat}/bin/socat -U - "UNIX-CONNECT:$sock" | while read -r line; do handle "$line"; done
    else
      apply_layout
    fi
  '';

  monitor-mirror-toggle = pkgs.writeShellScriptBin "hypr-monitor-mirror-toggle" ''
    INTERNAL=$(hyprctl monitors -j | jq -r '.[] | select(.name | contains("eDP")).name' | head -n1)
    EXTERNAL=$(hyprctl monitors -j | jq -r '.[] | select(.name | contains("eDP") | not) | select(.disabled == false).name' | head -n1)
    [ -z "$INTERNAL" ] || [ -z "$EXTERNAL" ] && { notify-send -u low "Need both monitors"; exit 0; }
    MIRRORED=$(hyprctl monitors -j | jq -r --arg e "$EXTERNAL" '.[] | select(.name == $e) | .mirrorOf // ""')
    if [ -n "$MIRRORED" ]; then
      hyprctl keyword monitor "$EXTERNAL,preferred,auto,1"
      notify-send -u low "Mirroring disabled"
    else
      hyprctl keyword monitor "$EXTERNAL,preferred,auto,1,mirror,$INTERNAL"
      notify-send -u low "Mirroring enabled"
    fi
  '';

  zoom-in = pkgs.writeShellScriptBin "hypr-zoom-in" ''
    # Always resolve the live Hyprland socket — the inherited HYPRLAND_INSTANCE_SIGNATURE
    # (e.g. from skwd-daemon's env) may point to a stale/crashed session. ss shows the
    # socket actually listening; fall back to ls -1t only if ss finds nothing.
    # Skip border theme in focus mode (borders are disabled)

    _sock=$(ss -xlp 2>/dev/null | grep -o "/run/user/1000/hypr/[^ ]*\.socket\.sock" | head -1)
    _sig=""
    [ -n "$_sock" ] && _sig="$(basename "$(dirname "$_sock")")"
    [ -z "$_sig" ] && _sig=$(ls -1t /run/user/1000/hypr 2>/dev/null | head -1)
    export HYPRLAND_INSTANCE_SIGNATURE="$_sig"
    NEW=$(hyprctl getoption cursor:zoom_factor -j | jq '.float + 1')
    hyprctl eval "hl.config({[\"cursor.zoom_factor\"]=$NEW})"
  '';
  zoom-reset = pkgs.writeShellScriptBin "hypr-zoom-reset" ''
    # Always resolve the live Hyprland socket — the inherited HYPRLAND_INSTANCE_SIGNATURE
    # (e.g. from skwd-daemon's env) may point to a stale/crashed session. ss shows the
    # socket actually listening; fall back to ls -1t only if ss finds nothing.
    # Skip border theme in focus mode (borders are disabled)

    _sock=$(ss -xlp 2>/dev/null | grep -o "/run/user/1000/hypr/[^ ]*\.socket\.sock" | head -1)
    _sig=""
    [ -n "$_sock" ] && _sig="$(basename "$(dirname "$_sock")")"
    [ -z "$_sig" ] && _sig=$(ls -1t /run/user/1000/hypr 2>/dev/null | head -1)
    export HYPRLAND_INSTANCE_SIGNATURE="$_sig"
    hyprctl eval "hl.config({[\"cursor.zoom_factor\"]=1})"
  '';

  wl-kbptr-launch = pkgs.writeShellScriptBin "wl-kbptr-launch" ''
    # Single-instance: kill any running wl-kbptr before launching a fresh one so
    # repeated RAlt taps can never stack overlays on top of each other.
    pkill -x wl-kbptr 2>/dev/null || true
    exec wl-kbptr -o modes=floating,click -o mode_floating.source=detect
  '';

  wl-kbptr-right-click = pkgs.writeShellScriptBin "wl-kbptr-right-click" ''
    # Same as wl-kbptr-launch but right-click instead of left-click.
    pkill -x wl-kbptr 2>/dev/null || true
    exec wl-kbptr -o modes=floating,click -o mode_floating.source=detect -o mode_click.button=right
  '';

  wl-kbptr-kill = pkgs.writeShellScriptBin "wl-kbptr-kill" ''
    # Panic exit: force-kill every wl-kbptr instance (clears a stacked/stranded overlay).
    pkill -9 -x wl-kbptr 2>/dev/null || true
  '';

  hypr-ws-next = pkgs.writeShellScriptBin "hypr-ws-next" ''
    set -euo pipefail
    CUR=$(hyprctl activeworkspace -j | jq '.id')
    NEXT=$(hyprctl workspaces -j | jq -r --argjson cur "$CUR" '
      [.[] | select(.windows > 0 and .id >= 1 and .id <= 10)] | sort_by(.id)
      | ((map(select(.id > $cur)) | .[0].id) // (.[0].id) // 1)
    ')
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"$NEXT\" }))"
  '';

  hypr-ws-prev = pkgs.writeShellScriptBin "hypr-ws-prev" ''
    set -euo pipefail
    CUR=$(hyprctl activeworkspace -j | jq '.id')
    PREV=$(hyprctl workspaces -j | jq -r --argjson cur "$CUR" '
      [.[] | select(.windows > 0 and .id >= 1 and .id <= 10)] | sort_by(.id)
      | ((map(select(.id < $cur)) | .[-1].id) // (.[-1].id) // 1)
    ')
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"$PREV\" }))"
  '';

  hypr-ws-focus = pkgs.writeShellScriptBin "hypr-ws-focus" ''
    [ -z "$1" ] && exit 1
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"$1\" }))"
  '';



  hypr-skwd-toggle = pkgs.writeShellScriptBin "hypr-skwd-toggle" ''
    # skwd-wall v2 picker. SKWD_WALL_OUTPUT pins the layer surface to the
    # focused monitor (v2 reads it before falling back to the "monitor" key).
    #
    # Focus mode: the wallpaper picker is not launchable — a new wallpaper
    # would re-fire the theme pipeline over the stripped-down scheme state
    # (and defeat the point of a static focus look). SUPER+CTRL+SPACE opens
    # the focus-scheme picker instead (quickshell IPC target "schemes").
    if [ -f "$HOME/.cache/focus-mode" ]; then
      qs -c desktop ipc call schemes toggle 2>/dev/null || true
      exit 0
    fi
    if pgrep -x skwd-wall-v2 >/dev/null 2>&1; then
      skwd-wall-v2 ui close 2>/dev/null || pkill -x skwd-wall-v2
    else
      FOCUSED_MONITOR=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .name')
      SKWD_WALL_OUTPUT="''${FOCUSED_MONITOR:-}" setsid skwd-wall-v2 >/dev/null 2>&1 &
    fi
  '';
  hypr-layout-toggle = pkgs.writeShellScriptBin "hypr-layout-toggle" ''
    WS=$(hyprctl activeworkspace -j | jq -r '.id')
    CUR=$(hyprctl activeworkspace -j | jq -r '.tiledLayout')

    if [ "$CUR" = "dwindle" ]; then
      NEW="scrolling"
    else
      NEW="dwindle"
    fi

    hyprctl eval "hl.workspace_rule({ workspace = '$WS', layout = '$NEW' })"

    # Workspace rules apply on workspace enter, so hop away and back
    NEXT=1
    [ "$WS" = "1" ] && NEXT=2
    hyprctl eval "hl.dsp.focus({ workspace = $NEXT })"
    sleep 0.1
    hyprctl eval "hl.dsp.focus({ workspace = $WS })"

    notify-send -u low "Layout: $NEW"
  '';

    arch-chroot = pkgs.writeShellScriptBin "arch" ''

    set -euo pipefail
    TARGET="/mnt/arch"
    UUID="40c435bc-9b32-470a-93cb-ce4bc318bbd9"
    DEVICE="/dev/disk/by-uuid/$UUID"

    # Check if the Arch drive is present
    if [ ! -e "$DEVICE" ]; then
      echo "Arch drive not found ($DEVICE). Plug in the USB drive first." >&2
      exit 1
    fi

    # Mount Arch partition if not already mounted (check both mountpoint and accessibility)
    if ! mountpoint -q "$TARGET" || ! ls "$TARGET/home" >/dev/null 2>&1; then
      sudo mkdir -p "$TARGET"
      sudo mount "$DEVICE" "$TARGET"
    fi

    # Verify mount succeeded
    if ! ls "$TARGET/home" >/dev/null 2>&1; then
      echo "Failed to mount Arch partition at $TARGET" >&2
      exit 1
    fi

    # Bind-mount virtual filesystems
    for fs in dev dev/pts proc sys run; do
      sudo mountpoint -q "$TARGET/$fs" || sudo mount --bind "/$fs" "$TARGET/$fs"
    done

    # Copy resolv.conf for network access
    sudo cp --remove-destination /etc/resolv.conf "$TARGET/etc/resolv.conf"

    # Chroot and login as nate
    sudo chroot "$TARGET" /bin/su - nate

    # Cleanup
    for fs in run sys proc dev/pts dev; do
      sudo umount "$TARGET/$fs" 2>/dev/null || true
    done
    sudo umount "$TARGET" 2>/dev/null || true
  '';


hypr-shot = pkgs.writeShellScriptBin "hypr-shot" ''
    MODE="''${1:-full}"
    DIR="$HOME/Pictures/Screenshots"
    mkdir -p "$DIR"

    FILE="$DIR/$(date +%Y-%m-%d_%H-%M-%S).png"

    _notify() {
      notify-send -a Screenshot "$1" 2>/dev/null ||
        dunstify -a Screenshot "$1" 2>/dev/null ||
        echo "[Screenshot] $1"
    }

    _cleanup() {
      [[ -n $PICKER_PID ]] && kill "$PICKER_PID" 2>/dev/null
    }
    trap _cleanup EXIT

    case "$MODE" in
      region)
        ACTIVE_WS=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .activeWorkspace.id')

        GEOS=$(hyprctl monitors -j 2>/dev/null | jq -r --arg ws "$ACTIVE_WS" '
          def fmt: .x as $x | .y as $y
            | (.width / .scale | floor) as $w
            | (.height / .scale | floor) as $h
            | .transform as $t
            | if $t == 1 or $t == 3 then "\($x),\($y) \($h)x\($w)"
              else "\($x),\($y) \($w)x\($h)" end;
          .[] | select(.activeWorkspace.id == ($ws | tonumber)) | fmt'
        )
        GEOS+=$'\n'
        GEOS+=$(hyprctl clients -j 2>/dev/null | jq -r --arg ws "$ACTIVE_WS" '
          .[] | select(.workspace.id == ($ws | tonumber) and .mapped == true and .hidden == false)
          | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
        )
        # Trim trailing newlines so slurp does not choke on empty lines
        GEOS=$(printf '%s' "$GEOS")

        hyprpicker -r -z >/dev/null 2>&1 &
        PICKER_PID=$!
        sleep .1

        SELECTION=$(echo "$GEOS" | slurp 2>/dev/null) || { _notify "Cancelled"; exit 1; }

        if [[ $SELECTION =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
          W=$((BASH_REMATCH[3]))
          H=$((BASH_REMATCH[4]))
          if (( W * H < 20 )); then
            CX=''${BASH_REMATCH[1]}
            CY=''${BASH_REMATCH[2]}
            while IFS= read -r rect; do
              [[ -z $rect ]] && continue
              if [[ $rect =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+) ]]; then
                RX=''${BASH_REMATCH[1]}
                RY=''${BASH_REMATCH[2]}
                RW=''${BASH_REMATCH[3]}
                RH=''${BASH_REMATCH[4]}
                if (( CX >= RX && CX < RX + RW && CY >= RY && CY < RY + RH )); then
                  SELECTION="''${RX},''${RY} ''${RW}x''${RH}"
                  break
                fi
              fi
            done <<< "$GEOS"
          fi
        fi

        grim -g "$SELECTION" "$FILE"
        LABEL="Region"
        ;;
      window)
        hyprpicker -r -z >/dev/null 2>&1 &
        PICKER_PID=$!
        sleep .1
        GEOMETRY=$(slurp -w) || { _notify "Cancelled"; exit 1; }
        grim -g "$GEOMETRY" "$FILE"
        LABEL="Window"
        ;;
      full|*)
        grim "$FILE"
        LABEL="Full screen"
        ;;
    esac

    [ -f "$FILE" ] && wl-copy -t image/png < "$FILE" 2>/dev/null
    _notify "$LABEL captured"
  '';


  # Always-on accelerometer-based screen rotation for eDP-1
  auto-rotate = pkgs.writeShellScriptBin "hypr-auto-rotate" ''
    ACCEL_DIR="/sys/bus/iio/devices/iio:device0"
    LAST=""

    discover_sig() {
      HYPRLAND_INSTANCE_SIGNATURE=""
      for d in /run/user/1000/hypr/*/; do
        s=$(basename "$d" 2>/dev/null) || continue
        if ${pkgs.hyprland}/bin/hyprctl --instance "$s" monitors -j >/dev/null 2>&1; then
          HYPRLAND_INSTANCE_SIGNATURE=$s; break
        fi
      done
      if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
        export HYPRLAND_INSTANCE_SIGNATURE
      fi
    }
    discover_sig
    # Daemon (Restart=always): no live compositor yet -> exit 1 so systemd retries.
    if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then exit 1; fi

    # Cache eDP name (rarely changes)
    EDP=""
    while true; do
      discover_sig
      [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ] && { sleep 2; continue; }
      # Refresh eDP name if we don't have it (first run or after disconnect)
      [ -z "$EDP" ] && EDP=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.name | contains("eDP")) | select(.disabled == false) | .name' | head -n1)
      [ -z "$EDP" ] && { sleep 2; continue; }
      X=$(cat "$ACCEL_DIR/in_accel_x_raw" 2>/dev/null || echo 0)
      Y=$(cat "$ACCEL_DIR/in_accel_y_raw" 2>/dev/null || echo 0)
      AX=''${X#-}
      AY=''${Y#-}
      if [ "$AY" -gt "$AX" ]; then
        if [ "$Y" -lt -500000 ]; then ORIENT="normal"
        elif [ "$Y" -gt 500000 ]; then ORIENT="invert"
        else ORIENT="$LAST"; fi
      else
        if [ "$X" -gt 500000 ]; then ORIENT="right"
        elif [ "$X" -lt -500000 ]; then ORIENT="left"
        else ORIENT="$LAST"; fi
      fi
      [ -z "$ORIENT" ] && ORIENT="normal"
      case "$ORIENT" in
        normal) T=0 ;;
        right)  T=1 ;;
        invert) T=2 ;;
        left)   T=3 ;;
        *)      T=0 ;;
      esac
      # Self-heal: also re-apply when the transform was reset externally
      # (hyprctl reload / monitor re-add re-apply the static config rule).
      CUR=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r --arg n "$EDP" '.[] | select(.name == $n) | .transform // 0' 2>/dev/null || echo "$T")
      if [ "$ORIENT" != "$LAST" ] || [ "$CUR" != "$T" ]; then
        MW=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r --arg n "$EDP" '.[] | select(.name == $n) | .width' 2>/dev/null || echo "2560")
        MH=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r --arg n "$EDP" '.[] | select(.name == $n) | .height' 2>/dev/null || echo "1600")
        MR=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r --arg n "$EDP" '.[] | select(.name == $n) | .refreshRate | floor' 2>/dev/null || echo "240")
        MODE=$(printf '%sx%s@%s' "$MW" "$MH" "$MR")
        ${pkgs.hyprland}/bin/hyprctl eval "hl.monitor({ output = \"$EDP\", mode = \"$MODE\", position = \"0x0\", scale = 1.25, transform = $T })" >/dev/null
        ${pkgs.hyprland}/bin/hyprctl eval "hl.config({input = {tablet = {transform = $T}, touchdevice = {transform = $T}}})" >/dev/null
        LAST="$ORIENT"
        # Reposition external monitor after rotation
        /etc/profiles/per-user/nate/bin/hypr-monitor-auto-layout >/dev/null 2>&1 &
        sleep 0.5
      else
        sleep 0.5
      fi
    done
  '';

in

{
  home.packages = with pkgs; [
    brightnessctl playerctl wl-clipboard cliphist grim slurp
    libnotify
    hyprlock hyprpicker wlogout pavucontrol gnome-calculator
    cava cmatrix
    wtype gamescope nautilus
    wiremix impala bluetui jellyfin-tui wf-recorder
    yazi
    wvkbd
    swaybg hyprsunset hypridle discord jq qt6.qtimageformats
    launch-tui audio-switch nightlight-toggle idle-toggle
    monitor-scaling monitor-internal-toggle monitor-mirror-toggle monitor-auto-layout auto-rotate hypr-skwd-toggle hypr-layout-toggle gaps-toggle pin-toggle zoom-in zoom-reset hypr-ws-next hypr-ws-prev hypr-ws-focus arch-chroot hypr-shot hyprland-border-theme
    wl-kbptr-launch wl-kbptr-right-click wl-kbptr-kill
  ];

  systemd.user.services.hypr-monitor-auto-layout = {
    Unit = {
      Description = "Hyprland monitor hotplug layout (Dell dock / laptop)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${monitor-auto-layout}/bin/hypr-monitor-auto-layout --listen";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";

    extraConfig = ''
      -- ═══ Environment ═══
      hl.env("QT_QPA_PLATFORM", "wayland")
      hl.env("SDL_VIDEODRIVER", "wayland")
      hl.env("CLUTTER_BACKEND", "wayland")
      hl.env("GDK_BACKEND", "wayland,x11")
      hl.env("XCURSOR_SIZE", "24")
      hl.env("XCURSOR_THEME", "Adwaita")
      -- Qt apps use gtk3 platform theme for dark mode
      hl.env("GTK_THEME", "MonoThemeDark")
      -- KDE Frameworks apps need this to read kdeglobals color scheme
      hl.env("XDG_CURRENT_DESKTOP", "Hyprland")

      -- ═══ Config ═══
      hl.config({
        ["general.border_size"] = 1,
        ["general.gaps_out"] = 14,
        ["general.gaps_in"]  = 8,
        ["general.col.active_border"]   = "rgba(adccd5ee)",
        ["general.col.inactive_border"] = "rgba(55555533)",
        ["decoration.rounding"] = 0,
        ["decoration.blur.enabled"] = true,
        ["decoration.blur.size"]   = 16,
        ["decoration.blur.passes"] = 3,
        ["decoration.blur.noise"]  = 0.0,
        ["decoration.blur.popups"] = true,
        ["decoration.blur.brightness"] = 0.5,
        ["decoration.dim_special"] = 0.35,
        ["decoration.blur.special"] = false,
        ["decoration.shadow.enabled"] = true,
        ["decoration.shadow.range"] = 16,
        ["decoration.shadow.color"] = "rgba(00000050)",
        ["group.groupbar.enabled"] = false,
        ["group.insert_after_current"] = true,
        ["group.col.border_active"]   = "rgba(e7bfa0ee)",
        ["group.col.border_inactive"] = "rgba(55555533)",
        ["dwindle.force_split"] = 0,
        ["dwindle.preserve_split"] = true,
        ["misc.force_default_wallpaper"] = -1,
        ["cursor.hide_on_key_press"] = true,
        ["render.direct_scanout"] = true,
      })

      -- Keep gamescope fullscreen so direct scanout stays engaged:
      -- a non-fullscreen gamescope window costs ~50% iGPU (Hyprland
      -- re-composites the 4K window per vblank -> gaming stutter).
      hl.window_rule({ match = { class = "^(gamescope)$" }, fullscreen = true })

      -- ═══ Layer blur ═══
      hl.layer_rule({match = {namespace = "omarchy-menu"}, blur = true})

      -- ═══ Omni menu: no compositor animation on the layer ═══
      -- The omni is a persistent surface resized 1x1 <-> full-screen at
      -- open/close. Hyprland treats that resize as a layer (re)show and
      -- plays the `layers` animation on it — the surface content scales
      -- from ~20% to 100% (verified frame-by-frame on an isolated output:
      -- the card's bbox grows 300x331 -> 1440x734 with easeOutQuint, while
      -- the QML content is a constant 720x800). no_anim keeps the resize
      -- instant so the QML enter choreography is the only motion.
      hl.layer_rule({match = {namespace = "omni-menu"}, no_anim = true})

      -- ═══ Input ═══
      hl.config({
        ["input.kb_layout"] = "us",
        ["input.kb_options"] = "compose:paus",
        ["input.repeat_rate"] = 40,
        ["input.repeat_delay"] = 600,
        ["input.numlock_by_default"] = true,
        ["input.touchpad.scroll_factor"] = 0.5,
        ["input.touchpad.natural_scroll"] = true,
      })

      -- ═══ Layer blur ═══

      -- ═══ Monitors ═══
      -- External 4K monitor: 4K@120Hz via Intel USB-C DP (no PRIME latency).
      hl.monitor({ output = "DP-1", mode = "3840x2160@120", position = "auto", scale = 1.25 })

      -- eDP-1: scale is pinned here so the very first monitor apply already
      -- carries the correct value. hypr-monitor-auto-layout still owns mode,
      -- position and transform at runtime (it disables eDP-1 when an external
      -- monitor is attached; auto-rotate re-applies mode+transform).
      --
      -- WHY: with no rule, Hyprland derives the scale from the panel's PPI
      -- (189 PPI -> getDefaultScale() 1.5 -> fractional search lands on 1.6).
      -- The layout script corrects it to 1.25 a moment later. hyprlock samples
      -- an output's fractional scale ONCE when it builds its session-lock
      -- surface, and the startup hook fires the layout and the first lock in the
      -- same burst -- so the first lock can be built against the unsettled scale.
      hl.monitor({ output = "eDP-1", scale = 1.25 })


      -- ═══ Workspace Names (Kanji) ═══
      hl.workspace_rule({ workspace = "1", default_name = "一" })
      hl.workspace_rule({ workspace = "2", default_name = "二" })
      hl.workspace_rule({ workspace = "3", default_name = "三" })
      hl.workspace_rule({ workspace = "4", default_name = "四" })
      hl.workspace_rule({ workspace = "5", default_name = "五" })
      hl.workspace_rule({ workspace = "6", default_name = "六" })
      hl.workspace_rule({ workspace = "7", default_name = "七" })
      hl.workspace_rule({ workspace = "8", default_name = "八" })
      hl.workspace_rule({ workspace = "9", default_name = "九" })
      hl.workspace_rule({ workspace = "10", default_name = "十" })

      -- ═══ Bezier Curves ═══
      hl.curve("easeOutQuint",     { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
      hl.curve("easeOutBounce",    { type = "bezier", points = { {0.68, -0.55}, {0.27, 1.55} } })
      hl.curve("easeInOutCubic",   { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
      hl.curve("linear",           { type = "bezier", points = { {0, 0}, {1, 1} } })
      hl.curve("almostLinear",     { type = "bezier", points = { {0.5, 0.5}, {0.75, 1.0} } })
      hl.curve("quick",            { type = "bezier", points = { {0.15, 0}, {0.1, 1} } })
      hl.curve("niercurve",        { type = "bezier", points = { {0.4, 0}, {0.2, 1} } })

      -- ═══ Animations ═══
      hl.animation({ leaf = "global",         enabled = true, speed = 10,    bezier = "default" })
      hl.animation({ leaf = "border",         enabled = true, speed = 5.39,  bezier = "easeOutQuint" })
      hl.animation({ leaf = "windows",        enabled = true, speed = 3,     bezier = "niercurve",     style = "slide" })
      hl.animation({ leaf = "windowsIn",      enabled = true, speed = 3,     bezier = "niercurve",     style = "slide" })
      hl.animation({ leaf = "windowsOut",     enabled = true, speed = 3,     bezier = "niercurve",     style = "slide" })
      hl.animation({ leaf = "fadeIn",         enabled = true, speed = 1.73,  bezier = "almostLinear" })
      hl.animation({ leaf = "fadeOut",        enabled = true, speed = 1.46,  bezier = "almostLinear" })
      hl.animation({ leaf = "fade",           enabled = true, speed = 3.03,  bezier = "quick" })
      hl.animation({ leaf = "layers",         enabled = true, speed = 3.81,  bezier = "easeOutQuint" })
      hl.animation({ leaf = "layersIn",       enabled = true, speed = 4,     bezier = "easeOutQuint",   style = "fade" })
      hl.animation({ leaf = "layersOut",      enabled = true, speed = 1.5,   bezier = "linear",         style = "fade" })
      hl.animation({ leaf = "fadeLayersIn",   enabled = true, speed = 1.79,  bezier = "almostLinear" })
      hl.animation({ leaf = "fadeLayersOut",  enabled = true, speed = 1.39,  bezier = "almostLinear" })
      hl.animation({ leaf = "workspaces",     enabled = true, speed = 4.5,   bezier = "easeOutQuint", style = "slide" })
      hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 5.0, bezier = "easeOutQuint", style = "slidevert bottom" })
      hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 5.0, bezier = "easeOutQuint", style = "slidevert top" })

      -- ═══ Window Rules ═══
      -- TUI floaters (SUPER+CTRL): pre-session popin 87% in/out.
      -- NOTE: match initial_title — the `animation` effect is DYNAMIC and
      -- re-evaluates against the LIVE title; these TUIs retitle themselves
      -- after launch (btop etc), which would drop the rule and make the
      -- close fall back to the global slide.
      hl.window_rule({ match = { initial_title = "^(tui-impala)$" },  animation = "popin 87%", float = true, center = true, size = { 900, 600 } })
      hl.window_rule({ match = { initial_title = "^(tui-btop)$" },    animation = "popin 87%", float = true, center = true, size = { 900, 600 } })
      hl.window_rule({ match = { initial_title = "^(tui-wiremix)$" }, animation = "popin 87%", float = true, center = true, size = { 900, 600 } })
      hl.window_rule({ match = { initial_title = "^(tui-bluetui)$" }, animation = "popin 87%", float = true, center = true, size = { 900, 600 } })
      hl.window_rule({ match = { initial_title = "^(tui-yazi)$" },    animation = "popin 87%", float = true, center = true, size = { 900, 600 } })
      hl.window_rule({ match = { initial_title = "^(tui-chat)$" },    animation = "popin 87%", float = true, center = true, size = { 900, 600 } })
      hl.window_rule({ match = { class = "^(xdg-desktop-portal-gtk)$" }, float = true, center = true, size = { 900, 600 } })
      hl.window_rule({ match = { initial_title = "^(yazi-file-chooser)$" }, animation = "popin 87%", float = true, center = true, size = { 900, 600 } })
      hl.window_rule({ match = { initial_title = "^(float-term)$" },  animation = "popin 87%", float = true, center = true, size = { 900, 600 } })

      -- ═══ Media windows — float ═══
      hl.window_rule({ match = { class = "^(imv)$" },              float = true, center = true, size = { 1200, 800 } })
      hl.window_rule({ match = { class = "^(mpv)$" },              float = true, center = true, size = { 1280, 720 } })
      hl.window_rule({ match = { class = "^(pinta)$" },            float = true, center = true, size = { 1200, 800 } })
      hl.window_rule({ match = { class = "^(swappy)$" },           float = true, center = true, size = { 900, 700 } })
      hl.window_rule({ match = { class = "^(obs)$" },              float = true, center = true })
      hl.window_rule({ match = { class = "^(kdenlive)$" },         float = true, center = true })
      hl.window_rule({ match = { class = "^(localsend_app)$" },    float = true, center = true, size = { 900, 700 } })



      -- ═══ Gestures ═══
      hl.gesture({ fingers = 3, direction = "swipe", action = "move", mods = "SUPER" })
      hl.gesture({ fingers = 4, direction = "swipe", action = "resize" })
      hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
      hl.gesture({ fingers = 3, direction = "down", action = "close", mods = "ALT" })
      hl.gesture({ fingers = 3, direction = "up", action = "fullscreen" })
      hl.gesture({ fingers = 3, direction = "down", action = "float" })



      -- ═══ Touch Device ═══
      hl.config({
        ["input.touchdevice.enabled"] = true,
      })

      -- ═══ Mouse Binds ═══
      hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
      hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

      -- ═══ Repeating Binds ═══
      hl.bind("XF86AudioRaiseVolume",    hl.dsp.exec_cmd("pamixer -i 5"),    { repeating = true })
      hl.bind("XF86AudioLowerVolume",    hl.dsp.exec_cmd("pamixer -d 5"),    { repeating = true })
      hl.bind("XF86AudioMute",           hl.dsp.exec_cmd("pamixer -t"),      { repeating = true })
      hl.bind("ALT + XF86AudioRaiseVolume", hl.dsp.exec_cmd("pamixer -i 1"), { repeating = true })
      hl.bind("ALT + XF86AudioLowerVolume", hl.dsp.exec_cmd("pamixer -d 1"), { repeating = true })
      hl.bind("XF86AudioMicMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { repeating = true })
      hl.bind("XF86MonBrightnessUp",     hl.dsp.exec_cmd("brightnessctl --device intel_backlight set +5%"),  { repeating = true })
      hl.bind("XF86MonBrightnessDown",   hl.dsp.exec_cmd("brightnessctl --device intel_backlight set 5%-"),  { repeating = true })
      hl.bind("SHIFT + XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl --device intel_backlight set 100%"), { repeating = true })
      hl.bind("SHIFT + XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl --device intel_backlight set 1%"),  { repeating = true })
      hl.bind("ALT + XF86MonBrightnessUp",     hl.dsp.exec_cmd("brightnessctl --device intel_backlight set +1%"), { repeating = true })
      hl.bind("ALT + XF86MonBrightnessDown",   hl.dsp.exec_cmd("brightnessctl --device intel_backlight set 1%-"), { repeating = true })
      -- External monitor brightness (DDC/CI via ext-brightness)
      hl.bind("SUPER + XF86MonBrightnessUp",   hl.dsp.exec_cmd("$HOME/.local/bin/ext-brightness up"),   { repeating = true })
      hl.bind("SUPER + XF86MonBrightnessDown", hl.dsp.exec_cmd("$HOME/.local/bin/ext-brightness down"), { repeating = true })
      hl.bind("SUPER + SHIFT + XF86MonBrightnessUp",   hl.dsp.exec_cmd("$HOME/.local/bin/ext-brightness max"), { repeating = true })
      hl.bind("SUPER + SHIFT + XF86MonBrightnessDown", hl.dsp.exec_cmd("$HOME/.local/bin/ext-brightness min"), { repeating = true })
      hl.bind("SUPER + ALT + XF86MonBrightnessUp",     hl.dsp.exec_cmd("$HOME/.local/bin/ext-brightness fine-up"), { repeating = true })
      hl.bind("SUPER + ALT + XF86MonBrightnessDown",   hl.dsp.exec_cmd("$HOME/.local/bin/ext-brightness fine-down"), { repeating = true })
      hl.bind("XF86KbdBrightnessUp",     hl.dsp.exec_cmd("$HOME/.local/bin/kb-backlight-osd up"), { repeating = true })
      hl.bind("XF86KbdBrightnessDown",   hl.dsp.exec_cmd("$HOME/.local/bin/kb-backlight-osd down"), { repeating = true })
      hl.bind("XF86TouchpadToggle",      hl.dsp.exec_cmd("hyprctl keyword device:touchpad:enabled toggle"), { repeating = true })

      -- ═══ Lock-Screen Binds ═══
      hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
      hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
      hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
      hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

      -- ═══ Window Management ═══
      hl.bind("SUPER + W", hl.dsp.window.close())
      hl.bind("CTRL + ALT + DELETE", function()
        for _, w in ipairs(hl.get_windows()) do
          hl.dispatch(hl.dsp.window.close({ window = "address:" .. w.address }))
        end
        hl.dispatch(hl.dsp.focus({ workspace = 1 }))
      end)
      hl.bind("SUPER + P",               hl.dsp.window.pseudo())
      hl.bind("SUPER + T",               hl.dsp.window.float())
      hl.bind("SUPER + F",               hl.dsp.window.fullscreen({ mode = 1 }))
      hl.bind("SUPER + ALT + F",          hl.dsp.window.fullscreen({ mode = 0 }))
      hl.bind("SUPER + CTRL + J",        hl.dsp.layout("togglesplit"))
      hl.bind("SUPER + O",               hl.dsp.exec_cmd("hypr-pin-toggle"))
      hl.bind("SUPER + CTRL + BACKSPACE", hl.dsp.exec_cmd("hypr-layout-toggle"))

      -- ╔═══ Keyboard Mouse (wl-kbptr) ═══
      -- Corne right-alt tap (ZMK &mt RALT F14) arrives at the compositor as
      -- keycode 192 = XF86Launch5 (xkb mapping). Bind that. F14 kept as a
      -- fallback in case the layout differs. Laptop right-alt = XF86Tools.
      hl.bind("XF86Launch5", hl.dsp.exec_cmd("wl-kbptr-launch"))
      hl.bind("XF86Tools", hl.dsp.exec_cmd("wl-kbptr-launch"))
      hl.bind("F13", hl.dsp.exec_cmd("wl-kbptr-launch"))
      hl.bind("F14", hl.dsp.exec_cmd("wl-kbptr-launch"))

      -- Shift + Right-Alt tap (Corne emits F14 on RAlt tap) = right-click
      hl.bind("SHIFT + XF86Launch5", hl.dsp.exec_cmd("wl-kbptr-right-click"))


      -- Move focus
      hl.bind("SUPER + H",     hl.dsp.focus({ direction = "l" }))
      hl.bind("SUPER + L",     hl.dsp.focus({ direction = "r" }))
      hl.bind("SUPER + K",     hl.dsp.focus({ direction = "u" }))
      hl.bind("SUPER + J",     hl.dsp.focus({ direction = "d" }))

      -- Workspace switching
      hl.bind("SUPER + 1", hl.dsp.focus({ workspace = 1 }))
      hl.bind("SUPER + 2", hl.dsp.focus({ workspace = 2 }))
      hl.bind("SUPER + 3", hl.dsp.focus({ workspace = 3 }))
      hl.bind("SUPER + 4", hl.dsp.focus({ workspace = 4 }))
      hl.bind("SUPER + 5", hl.dsp.focus({ workspace = 5 }))
      hl.bind("SUPER + 6", hl.dsp.focus({ workspace = 6 }))
      hl.bind("SUPER + 7", hl.dsp.focus({ workspace = 7 }))
      hl.bind("SUPER + 8", hl.dsp.focus({ workspace = 8 }))
      hl.bind("SUPER + 9", hl.dsp.focus({ workspace = 9 }))
      hl.bind("SUPER + 0", hl.dsp.focus({ workspace = 10 }))

      -- Move window to workspace (with follow)
      hl.bind("SUPER + SHIFT + 1", hl.dsp.window.move({ workspace = 1, follow = true }))
      hl.bind("SUPER + SHIFT + 2", hl.dsp.window.move({ workspace = 2, follow = true }))
      hl.bind("SUPER + SHIFT + 3", hl.dsp.window.move({ workspace = 3, follow = true }))
      hl.bind("SUPER + SHIFT + 4", hl.dsp.window.move({ workspace = 4, follow = true }))
      hl.bind("SUPER + SHIFT + 5", hl.dsp.window.move({ workspace = 5, follow = true }))
      hl.bind("SUPER + SHIFT + 6", hl.dsp.window.move({ workspace = 6, follow = true }))
      hl.bind("SUPER + SHIFT + 7", hl.dsp.window.move({ workspace = 7, follow = true }))
      hl.bind("SUPER + SHIFT + 8", hl.dsp.window.move({ workspace = 8, follow = true }))
      hl.bind("SUPER + SHIFT + 9", hl.dsp.window.move({ workspace = 9, follow = true }))
      hl.bind("SUPER + SHIFT + 0", hl.dsp.window.move({ workspace = 10, follow = true }))

      -- Move window to workspace (silent, no follow)
      hl.bind("SUPER + SHIFT + ALT + 1", hl.dsp.window.move({ workspace = 1, follow = false }))
      hl.bind("SUPER + SHIFT + ALT + 2", hl.dsp.window.move({ workspace = 2, follow = false }))
      hl.bind("SUPER + SHIFT + ALT + 3", hl.dsp.window.move({ workspace = 3, follow = false }))
      hl.bind("SUPER + SHIFT + ALT + 4", hl.dsp.window.move({ workspace = 4, follow = false }))
      hl.bind("SUPER + SHIFT + ALT + 5", hl.dsp.window.move({ workspace = 5, follow = false }))
      hl.bind("SUPER + SHIFT + ALT + 6", hl.dsp.window.move({ workspace = 6, follow = false }))
      hl.bind("SUPER + SHIFT + ALT + 7", hl.dsp.window.move({ workspace = 7, follow = false }))
      hl.bind("SUPER + SHIFT + ALT + 8", hl.dsp.window.move({ workspace = 8, follow = false }))
      hl.bind("SUPER + SHIFT + ALT + 9", hl.dsp.window.move({ workspace = 9, follow = false }))
      hl.bind("SUPER + SHIFT + ALT + 0", hl.dsp.window.move({ workspace = 10, follow = false }))

      -- Special workspace (scratchpad)
      hl.bind("SUPER + S", hl.dsp.workspace.toggle_special("scratchpad"), { release = true })
      hl.bind("SUPER + ALT + S", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

      -- Workspace navigation
      hl.bind("SUPER + TAB",          hl.dsp.exec_cmd("hypr-ws-next"))
      hl.bind("SUPER + SHIFT + TAB",  hl.dsp.exec_cmd("hypr-ws-prev"))
      hl.bind("SUPER + CTRL + TAB",   hl.dsp.focus({ workspace = "previous" }))

      -- Move workspace to monitor
      hl.bind("SUPER + ALT + H",            hl.dsp.workspace.move({ monitor = "l" }))
      hl.bind("SUPER + ALT + L",            hl.dsp.workspace.move({ monitor = "r" }))
      hl.bind("SUPER + ALT + K",            hl.dsp.workspace.move({ monitor = "u" }))
      hl.bind("SUPER + ALT + J",            hl.dsp.workspace.move({ monitor = "d" }))

      -- Swap windows
      hl.bind("SUPER + SHIFT + H",     hl.dsp.window.move({ direction = "l" }))
      hl.bind("SUPER + SHIFT + L",     hl.dsp.window.move({ direction = "r" }))

      -- Resize windows
      hl.bind("SUPER + left",  hl.dsp.window.resize({ x = -60, y = 0, relative = true }))
      hl.bind("SUPER + down",  hl.dsp.window.resize({ x = 0, y = 60, relative = true }))
      hl.bind("SUPER + up",    hl.dsp.window.resize({ x = 0, y = -60, relative = true }))
      hl.bind("SUPER + right", hl.dsp.window.resize({ x = 60, y = 0, relative = true }))

      hl.bind("SUPER + SHIFT + K",     hl.dsp.window.move({ direction = "u" }))
      hl.bind("SUPER + SHIFT + J",     hl.dsp.window.move({ direction = "d" }))

      -- Alt-Tab cycle focus
      hl.bind("ALT + TAB", function()
        hl.dispatch(hl.dsp.window.cycle_next())
        hl.dispatch(hl.dsp.window.bring_to_top())
      end)
      hl.bind("ALT + SHIFT + TAB", function()
        hl.dispatch(hl.dsp.window.cycle_next({ next = false }))
        hl.dispatch(hl.dsp.window.bring_to_top())
      end)

      -- Focus monitor
      hl.bind("CTRL + ALT + TAB",           hl.dsp.focus({ monitor = "+1" }))
      hl.bind("CTRL + ALT + SHIFT + TAB",   hl.dsp.focus({ monitor = "-1" }))

      -- Resize active window
      hl.bind("SUPER + minus",         hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
      hl.bind("SUPER + equal",         hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
      hl.bind("SUPER + SHIFT + minus", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
      hl.bind("SUPER + SHIFT + equal", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))

      -- Groups
      hl.bind("SUPER + G",                      hl.dsp.group.toggle())
      hl.bind("SUPER + ALT + G",                hl.dsp.window.move({ out_of_group = true }))
      hl.bind("SUPER + ALT + left",             hl.dsp.window.move({ into_group = "l" }))
      hl.bind("SUPER + ALT + right",            hl.dsp.window.move({ into_group = "r" }))
      hl.bind("SUPER + ALT + up",               hl.dsp.window.move({ into_group = "u" }))
      hl.bind("SUPER + ALT + down",             hl.dsp.window.move({ into_group = "d" }))
      hl.bind("SUPER + ALT + TAB",              hl.dsp.group.next())
      hl.bind("SUPER + SHIFT + B",           hl.dsp.exec_cmd("qs -c desktop ipc call battery toggle"))
      hl.bind("SUPER + SHIFT + C",           hl.dsp.exec_cmd("qs -c desktop ipc call calendar toggle"))
      hl.bind("SUPER + SHIFT + W",           hl.dsp.exec_cmd("qs -c desktop ipc call weather toggle"))
      hl.bind("SUPER + ALT + SHIFT + TAB",      hl.dsp.group.prev())
      hl.bind("SUPER + bracketleft",            hl.dsp.group.prev())
      hl.bind("SUPER + bracketright",           hl.dsp.group.next())
      hl.bind("SUPER + ALT + 1", hl.dsp.group.active({ index = 1 }))
      hl.bind("SUPER + ALT + 2", hl.dsp.group.active({ index = 2 }))
      hl.bind("SUPER + ALT + 3", hl.dsp.group.active({ index = 3 }))
      hl.bind("SUPER + ALT + 4", hl.dsp.group.active({ index = 4 }))
      hl.bind("SUPER + ALT + 5", hl.dsp.group.active({ index = 5 }))

      -- Monitor scaling
      -- Mini-LED toggle
      hl.bind("SUPER + slash", hl.dsp.exec_cmd("sudo mini-led-toggle"))

      -- Mouse scroll workspace / group
      hl.bind("SUPER + mouse_down",      hl.dsp.exec_cmd("hypr-ws-next"))
      hl.bind("SUPER + mouse_up",        hl.dsp.exec_cmd("hypr-ws-prev"))
      hl.bind("SUPER + ALT + mouse_down", hl.dsp.group.next())
      hl.bind("SUPER + ALT + mouse_up",   hl.dsp.group.prev())

      -- ═══ Audio / Media ═══
      hl.bind("SUPER + XF86AudioMute",   hl.dsp.exec_cmd("hypr-audio-switch"))
      hl.bind("SUPER + B", hl.dsp.exec_cmd("playerctl previous"))
      hl.bind("SUPER + M", hl.dsp.exec_cmd("playerctl play-pause"))
      hl.bind("SUPER + N", hl.dsp.exec_cmd("playerctl next"))
      hl.bind("SUPER + XF86AudioLowerVolume", hl.dsp.exec_cmd("brightnessctl --device intel_backlight set 10%-"))
      hl.bind("SUPER + XF86AudioRaiseVolume", hl.dsp.exec_cmd("brightnessctl --device intel_backlight set +10%"))
      hl.bind("CTRL + XF86AudioRaiseVolume",  hl.dsp.exec_cmd("brightnessctl --device intel_backlight set +10%"))
      -- Monitor brightness via DDC/CI
      hl.bind("SUPER + ALT + XF86AudioRaiseVolume", hl.dsp.exec_cmd("$HOME/.local/bin/monitor-brightness up"),   { repeating = true })
      hl.bind("SUPER + ALT + XF86AudioLowerVolume", hl.dsp.exec_cmd("$HOME/.local/bin/monitor-brightness down"), { repeating = true })

      -- ═══ Clipboard ═══
      hl.bind("SUPER + C", hl.dsp.send_shortcut({ mods = "CTRL", key = "Insert" }))
      hl.bind("SUPER + V", hl.dsp.send_shortcut({ mods = "SHIFT", key = "Insert" }))
      hl.bind("SUPER + X", hl.dsp.send_shortcut({ mods = "CTRL", key = "X" }))
      hl.bind("SUPER + CTRL + V", hl.dsp.exec_cmd("qs -c desktop ipc call palette openCategory Clipboard"))

      -- ═══ Apps ═══
      hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("qs -c desktop ipc call palette toggle"))
      -- hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("foot"))  # removed, use SUPER + Q
      -- hl.bind("SUPER + ALT + RETURN", hl.dsp.exec_cmd("foot -e tmux"))  # removed, use SUPER + ALT + Q
      -- hl.bind("SUPER + CTRL + RETURN", hl.dsp.exec_cmd("foot --title=float-term"))  # removed, use SUPER + CTRL + Q
      hl.bind("SUPER + Q", hl.dsp.exec_cmd("foot"))
      hl.bind("SUPER + CTRL + Q", hl.dsp.exec_cmd("foot --title=float-term"))
      -- hl.bind("SUPER + SHIFT + RETURN", hl.dsp.exec_raw("$HOME/.local/bin/zen-launch"))  # removed, use SUPER + Z
      -- hl.bind("SUPER + SHIFT + B", hl.dsp.exec_raw("$HOME/.local/bin/zen-launch"))  # removed, use SUPER + Z
      hl.bind("SUPER + Z", hl.dsp.exec_raw("$HOME/.local/bin/zen-launch"))
      hl.bind("SUPER + C", hl.dsp.exec_raw("$HOME/.local/bin/chromium-launch"))
      hl.bind("SUPER + SHIFT + F",     hl.dsp.exec_cmd("nautilus --new-window"))
      -- hl.bind("SUPER + SHIFT + ALT + F", hl.dsp.exec_cmd("nautilus ."))  # removed
      hl.bind("SUPER + CTRL + F", hl.dsp.exec_cmd("launch-tui yazi yazi"))
      hl.bind("SUPER + E", hl.dsp.exec_cmd("foot -e nvim"))
      -- hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd("vesktop"))  # removed
      hl.bind("SUPER + SHIFT + G", hl.dsp.exec_cmd("$HOME/.local/bin/gamescope-bigpicture"))

      -- TUI panels (float via windowrule)
      hl.bind("SUPER + CTRL + W", hl.dsp.exec_cmd("launch-tui impala impala"))
      hl.bind("SUPER + CTRL + T", hl.dsp.exec_cmd("launch-tui btop btop"))
      hl.bind("SUPER + CTRL + A", hl.dsp.exec_cmd("launch-tui wiremix wiremix"))
      hl.bind("SUPER + ALT + SPACE", hl.dsp.exec_cmd("launch-tui chat tui-chat"))
      hl.bind("SUPER + CTRL + B", hl.dsp.exec_cmd("rfkill unblock bluetooth; launch-tui bluetui bluetui"))

      -- ═══ System ═══
      hl.bind("SUPER + CTRL + L",         hl.dsp.exec_cmd("systemd-run --user --unit=power-btn-lock $HOME/.local/bin/power-btn-lock"))
      hl.bind("PRINT", hl.dsp.exec_cmd("hypr-shot full"))
      hl.bind("ALT + PRINT", hl.dsp.exec_cmd("wf-recorder"))
      hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("hypr-shot region"))
      hl.bind("SUPER + PRINT", hl.dsp.exec_cmd("pkill hyprpicker || hyprpicker -a"))
      hl.bind("SUPER + CTRL + SHIFT + S", hl.dsp.exec_cmd("hypr-shot full"))
      hl.bind("SUPER + ESCAPE", hl.dsp.exec_cmd("qs -c desktop ipc call palette openCategory System"))
      -- hl.bind("SUPER + K", ...)  # removed
      hl.bind("SUPER + CTRL + E", hl.dsp.exec_cmd("qs -c desktop ipc call palette openCategory Emoji"))
      hl.bind("SUPER + CTRL + Z", hl.dsp.exec_cmd("hypr-zoom-in"))
      hl.bind("SUPER + CTRL + SHIFT + Z", hl.dsp.exec_cmd("hypr-zoom-reset"))
      -- hl.bind("SUPER + BACKSPACE", ...)  # removed, opacity toggle
      hl.bind("SUPER + SHIFT + BACKSPACE", hl.dsp.exec_cmd("hypr-gaps-toggle"))
      hl.bind("SUPER + SHIFT + ESCAPE", hl.dsp.exec_cmd("hypr-focus-toggle"))
      -- hl.bind("SUPER + CTRL + BACKSPACE", hl.dsp.exec_cmd("hyprctl keyword dwindle:force_split toggle 0 2"))  # replaced by layout-toggle
      hl.bind("SUPER + CTRL + N", hl.dsp.exec_cmd("hypr-nightlight-toggle"))
      hl.bind("SUPER + CTRL + I", hl.dsp.exec_cmd("hypr-idle-toggle"))
      hl.bind("SUPER + CTRL + DELETE", hl.dsp.exec_cmd("hypr-monitor-internal-toggle"))
      hl.bind("SUPER + CTRL + ALT + DELETE", hl.dsp.exec_cmd("hypr-monitor-mirror-toggle"))
      -- auto-rotate is always on, started at boot
      hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("hyprctl keyword monitor eDP-1,disable"))
      hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("hypr-monitor-auto-layout"))
      hl.bind("XF86Calculator", hl.dsp.exec_cmd("gnome-calculator"))

      -- ═══ NYI ═══
      -- hl.bind("SUPER + CTRL + O",     hl.dsp.exec_cmd("notify-send 'NYI' 'Toggle menu'"))  # removed NYI
      -- hl.bind("SUPER + CTRL + H",     hl.dsp.exec_cmd("notify-send 'NYI' 'Hardware menu'"))  # removed NYI
      hl.bind("SUPER + CTRL + SPACE", hl.dsp.exec_cmd("hypr-skwd-toggle"))
      -- hl.bind("SUPER + ALT + SPACE",   hl.dsp.exec_cmd("qs -c desktop ipc call palette quick"))  # replaced by tui-chat
      -- hl.bind("SUPER + CTRL + PERIOD", hl.dsp.exec_cmd("notify-send 'NYI' 'Transcode'"))  # removed NYI
      -- hl.bind("SUPER + CTRL + R",     hl.dsp.exec_cmd("notify-send 'NYI' 'Set reminder'"))  # removed NYI
      -- hl.bind("SUPER + CTRL + ALT + R", hl.dsp.exec_cmd("notify-send 'NYI' 'Show reminders'"))  # removed NYI
      -- hl.bind("SUPER + SHIFT + CTRL + R", hl.dsp.exec_cmd("notify-send 'NYI' 'Clear reminders'"))  # removed NYI

      hl.bind("XF86PowerOff", hl.dsp.exec_cmd("systemd-run --user --unit=power-btn-lock $HOME/.local/bin/power-btn-lock"))

      -- ═══ Startup ═══
      hl.on("hyprland.start", function()
        hl.exec_cmd("hypr-monitor-auto-layout")

        hl.exec_cmd("systemctl --user start hypr-monitor-auto-layout.service")
        -- hl.exec_cmd("hypr-auto-rotate") -- managed by systemd service
        hl.exec_cmd("wl-paste --type text --watch cliphist store")
        hl.exec_cmd("wl-paste --type image --watch cliphist store")
        hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY QT_QPA_PLATFORM DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_COLOR_SCHEME GTK_THEME XDG_DATA_DIRS HYPRLAND_INSTANCE_SIGNATURE && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_COLOR_SCHEME GTK_THEME XDG_DATA_DIRS HYPRLAND_INSTANCE_SIGNATURE")
        hl.exec_cmd("systemctl --user restart xdg-desktop-portal-gtk.service")
        hl.exec_cmd("systemctl --user start skwd-walld")
        -- Focus mode persists as a guard file, but the compositor settings
        -- (no gaps/borders/shadow/blur/animations) live only in the running
        -- session, and skwd-walld's boot restore runs matugen against the
        -- flat focus wallpaper — overwriting the app themes with its
        -- fallback palette. This re-asserts the compositor settings and
        -- re-runs the scheme apply. No-op when focus mode is off.
        hl.exec_cmd("focus-boot-apply")
        -- Quickshell is started via its systemd unit so exactly one process
        -- owns the shell (see the note below). It inherits the live
        -- HYPRLAND_INSTANCE_SIGNATURE from the import-environment call above.
        -- Start the UNIT rather than a bare binary: systemd must own the
        -- shell, otherwise refresh_shell()'s `systemctl restart` spawns a
        -- SECOND copy (the hook-launched one is invisible to the unit) and
        -- the user gets a duplicate bar. The unit inherits the live
        -- HYPRLAND_INSTANCE_SIGNATURE from the import-environment call above.
        hl.exec_cmd("systemctl --user start quickshell-desktop")
        hl.exec_cmd("hyprland-border-theme")
        hl.exec_cmd("kdeconnectd")
        -- Rename persistent workspaces to kanji
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 1, name = "一" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 2, name = "二" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 3, name = "三" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 4, name = "四" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 5, name = "五" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 6, name = "六" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 7, name = "七" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 8, name = "八" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 9, name = "九" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 10, name = "十" }))
        -- Startup lock via the wrapper: it records the monitor scale the lock
        -- was built against (see home/nate/bin/lock-at-startup) so the
        -- first-lock scale race can be confirmed from data, not inferred.
        hl.exec_cmd("lock-at-startup")
      end)

      -- ═══ Focus mode re-assert (survives autoreload) ═══
      -- Hyprland's autoreload is ON, so every rebuild rewrites this file and
      -- silently reloads the config, wiping the focus-mode compositor
      -- settings (they live only in the running session). The start hook
      -- only covers login. This guarded block is the LAST writer on every
      -- parse, so focus mode survives a mid-session rebuild too. Values must
      -- stay in sync with focus_compositor_apply() in bin/hypr-focus-toggle.
      do
        local _guard = io.open(os.getenv("HOME") .. "/.cache/focus-mode", "r")
        if _guard then
          _guard:close()
          hl.config({
            ["general.border_size"] = 0,
            ["general.gaps_out"] = 0,
            ["general.gaps_in"] = 0,
            ["general.col.active_border"]   = "rgba(00000000)",
            ["general.col.inactive_border"] = "rgba(00000000)",
            ["group.col.border_active"]     = "rgba(00000000)",
            ["group.col.border_inactive"]   = "rgba(00000000)",
            ["decoration.rounding"] = 0,
            ["decoration.shadow.enabled"] = false,
            ["decoration.blur.enabled"] = false,
            ["decoration.blur.brightness"] = 1.0,
            ["decoration.dim_special"] = 0.0,
            ["animations.enabled"] = false,
          })
        end
      end
    '';
  };

  # tui-chat: AI chat client launched by SUPER+ALT+SPACE
  home.file.".local/bin/tui-chat" = {
    source = ./tui-chat.py;
    executable = true;
  };
}
