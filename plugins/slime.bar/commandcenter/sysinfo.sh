#!/usr/bin/env bash
# One JSON sample of system stats for the command centre's System tab.
# CPU usage is computed by the caller from the cumulative /proc/stat counters.
set -uo pipefail

read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
cpu_busy=$((user + nice + system + irq + softirq + steal))
cpu_total=$((cpu_busy + idle + iowait))

mem=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2}
  END {printf "%d %d %d %d", t, t-a, st, st-sf}' /proc/meminfo)
read -r mem_total mem_used swap_total swap_used <<< "$mem"

cpu_temp=0
for h in /sys/class/hwmon/hwmon*; do
  if [[ $(cat "$h/name" 2>/dev/null) =~ ^(k10temp|coretemp|zenpower)$ ]]; then
    cpu_temp=$(( $(cat "$h/temp1_input" 2>/dev/null || echo 0) / 1000 ))
    break
  fi
done

gpu='null'
if command -v nvidia-smi >/dev/null; then
  if g=$(nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu \
      --format=csv,noheader,nounits 2>/dev/null | head -1); then
    IFS=',' read -r gname gutil gused gtotal gtemp <<< "$g"
    gpu=$(jq -cn --arg n "${gname# }" --argjson u "${gutil// /}" --argjson m "${gused// /}" \
      --argjson t "${gtotal// /}" --argjson c "${gtemp// /}" '{name:$n, util:$u, memUsed:$m, memTotal:$t, temp:$c}')
  fi
fi

disks=$(df -B1 --output=target,size,used -x tmpfs -x devtmpfs -x efivarfs -x overlay 2>/dev/null \
  | awk 'NR>1 && ($1=="/" || $1=="/home") {printf "%s{\"mount\":\"%s\",\"size\":%s,\"used\":%s}", (n++?",":""), $1, $2, $3}')

procs=$(ps -eo pcpu=,rss=,comm= --sort=-pcpu | head -5 \
  | awk '{c=$3; for(i=4;i<=NF;i++) c=c" "$i; gsub(/"/,"",c); printf "%s{\"cpu\":%s,\"mem\":%s,\"name\":\"%s\"}", (n++?",":""), $1, $2*1024, c}')

printf '{"cpuBusy":%s,"cpuTotal":%s,"memTotal":%s,"memUsed":%s,"swapTotal":%s,"swapUsed":%s,"cpuTemp":%s,"gpu":%s,"disks":[%s],"procs":[%s],"load":"%s"}\n' \
  "$cpu_busy" "$cpu_total" "$((mem_total * 1024))" "$((mem_used * 1024))" "$((swap_total * 1024))" "$((swap_used * 1024))" \
  "$cpu_temp" "$gpu" "$disks" "$procs" "$(cut -d' ' -f1-3 /proc/loadavg)"
