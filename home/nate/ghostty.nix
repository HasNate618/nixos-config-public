{ pkgs, ... }: {
  programs.ghostty = {
    enable = true;
    settings = {
      font-family = "JetBrainsMono Nerd Font";
      font-style = "Regular";
      font-size = 11;
      window-theme = "dark";
      window-padding-x = 14;
      window-padding-y = 14;
      confirm-close-surface = false;
      resize-overlay = "never";
      background-opacity = 0.8;
      cursor-style = "block";
      cursor-style-blink = false;
      shell-integration-features = [ "no-cursor" "ssh-env" ];
      mouse-scroll-multiplier = 0.95;
      gtk-toolbar-style = "flat";
      async-backend = "epoll";
      # Include matugen-generated colors from skwd-wall
      theme = "skwd-theme";
      custom-shader = "shaders/cursor_sweep.glsl";
      keybind = [
        "shift+insert=paste_from_clipboard"
        "control+insert=copy_to_clipboard"
        "super+control+shift+alt+arrow_down=resize_split:down,100"
        "super+control+shift+alt+arrow_up=resize_split:up,100"
        "super+control+shift+alt+arrow_left=resize_split:left,100"
        "super+control+shift+alt+arrow_right=resize_split:right,100"
      ];
    };
  };

  # Custom cursor sweep shader — animated trail effect
  xdg.configFile."ghostty/shaders/cursor_sweep.glsl".text = ''
    vec3 sRGBToLinear(vec3 c) {
        return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
    }
    vec4 TRAIL_COLOR = vec4(sRGBToLinear(iCurrentCursorColor.rgb), iCurrentCursorColor.a);
    const float DURATION = 0.2;
    const float TRAIL_LENGTH = 0.5;
    const float BLUR = 2.0;
    float ease(float x) { return 1.0 - pow(1.0 - x, 3.0); }
    float getSdfRectangle(vec2 point, vec2 center, vec2 halfSize) {
        vec2 d = abs(point - center) - halfSize;
        return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    }
    float seg(vec2 p, vec2 a, vec2 b, inout float s, float d) {
        vec2 e = b - a; vec2 w = p - a;
        vec2 proj = a + e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
        float segd = dot(p - proj, p - proj); d = min(d, segd);
        float c0 = step(0.0, p.y - a.y), c1 = 1.0 - step(0.0, p.y - b.y);
        float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);
        float allCond = c0 * c1 * c2, noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);
        s *= mix(1.0, -1.0, step(0.5, allCond + noneCond)); return d;
    }
    float getSdfParallelogram(vec2 p, vec2 v0, vec2 v1, vec2 v2, vec2 v3) {
        float s = 1.0; float d = dot(p - v0, p - v0);
        d = seg(p, v0, v3, s, d); d = seg(p, v1, v0, s, d);
        d = seg(p, v2, v1, s, d); d = seg(p, v3, v2, s, d); return s * sqrt(d);
    }
    vec2 normalize(vec2 value, float isPosition) {
        return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
    }
    float antialising(float d) { return 1.0 - smoothstep(0.0, normalize(vec2(BLUR, BLUR), 0.0).x, d); }
    float getTopVertexFlag(vec2 a, vec2 b) {
        return 1.0 - max(step(b.x, a.x) * step(a.y, b.y), step(a.x, b.x) * step(b.y, a.y));
    }
    void mainImage(out vec4 fragColor, in vec2 fragCoord) {
        fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
        vec2 vu = normalize(fragCoord, 1.0), offsetFactor = vec2(-0.5, 0.5);
        vec4 cur = vec4(normalize(iCurrentCursor.xy, 1.0), normalize(iCurrentCursor.zw, 0.0));
        vec4 prev = vec4(normalize(iPreviousCursor.xy, 1.0), normalize(iPreviousCursor.zw, 0.0));
        vec2 ccC = cur.xy - cur.zw * offsetFactor, ccP = prev.xy - prev.zw * offsetFactor;
        float sdfCur = getSdfRectangle(vu, ccC, cur.zw * 0.5);
        float lineLen = distance(ccC, ccP), minDist = cur.w * 1.5;
        float progress = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
        vec4 newC = fragColor;
        if (lineLen > minDist) {
            float sf = ease(progress);
            vec2 d = abs(ccC - ccP); float t = 0.001;
            float isStraight = max(step(d.y, t), step(d.x, t));
            float tvf = getTopVertexFlag(cur.xy, prev.xy), bvf = 1.0 - tvf;
            vec2 v0 = vec2(cur.x + cur.z * tvf, cur.y - cur.w);
            vec2 v1 = vec2(cur.x + cur.z * bvf, cur.y);
            vec2 v2f = vec2(prev.x + cur.z * bvf, prev.y);
            vec2 v3f = vec2(prev.x + cur.z * tvf, prev.y - prev.w);
            vec2 v2s = mix(v1, v2f, TRAIL_LENGTH), v3s = mix(v0, v3f, TRAIL_LENGTH);
            float sdfDiag = getSdfParallelogram(vu, v0, v1, mix(v2s, v1, sf), mix(v3s, v0, sf));
            vec2 mn = min(ccP, ccC), mx = max(ccP, ccC);
            vec2 bf = (mx - mn) + cur.zw, bc = (mn + mx) * 0.5;
            vec2 bs = mix(cur.zw, bf, TRAIL_LENGTH), bcs = mix(ccC, bc, TRAIL_LENGTH);
            float sdfRect = getSdfRectangle(vu, mix(bcs, ccC, sf), mix(bs, cur.zw, sf) * 0.5);
            float sdfTrail = mix(sdfDiag, sdfRect, isStraight);
            float ta = antialising(sdfTrail);
            newC = mix(newC, TRAIL_COLOR, ta);
            newC = mix(newC, fragColor, step(sdfCur, 0.0));
        }
        fragColor = newC;
    }
  '';
}