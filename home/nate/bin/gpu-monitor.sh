#!/run/current-system/sw/bin/bash
# GPU/iGPU gaming monitor — logs profile, display Hz, iGPU RCS busy, nvidia util
# every 10s so a transient "smooth 25%" window during gaming can be explained.
# Log: /tmp/gpu-monitor.log   Stop: pkill -f gpu-monitor
LOG=/tmp/gpu-monitor.log
: > "$LOG"
# intel_gpu_top is started separately (needs sudo + perf; run as its own bg process:
#   sudo intel_gpu_top -s 15000 -o /tmp/igt-monitor.txt
echo "$(date +%H:%M:%S) monitor started (10s cadence)" >> "$LOG"
while true; do
  export HYPRLAND_INSTANCE_SIGNATURE=$(ls -d /run/user/1000/hypr/*/ 2>/dev/null | tail -1 | xargs basename 2>/dev/null || echo "")
  RCS=$(tail -1 /tmp/igt-monitor.txt 2>/dev/null | awk '{print $7}')
  PROFILE=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null)
  HZ=$(hyprctl monitors -j 2>/dev/null | jq -r '[.[] | .name + "=" + (.refreshRate | tostring)] | join(" ")')
  NV=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader 2>/dev/null | tr -d ' %')
  GS=$(pgrep -c -x gamescope 2>/dev/null || echo 0)
  FR=$(pgrep -c -x vkd3d-proton 2>/dev/null; pgrep -c -f 'reaper' 2>/dev/null)
  echo "$(date +%H:%M:%S) profile=$PROFILE hz=$HZ igpu_rcs=${RCS:-?}% nvidia=${NV:-?}% gamescope=$GS" >> "$LOG"
  sleep 10
done
