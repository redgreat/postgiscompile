#!/usr/bin/env bash

set -euo pipefail

# 函数: 初始化输出目录
init_output_dir() {
  : "${OUT_DIR:=/var/log/monitor_pg}"
  mkdir -p "$OUT_DIR"
  : "${OUT_FILE:=${OUT_DIR}/collector.jsonl}"
}

# 函数: 采集CPU使用信息
collect_cpu() {
  local user1 nice1 system1 idle1 iowait1 irq1 softirq1 steal1 guest1 guest_nice1
  read -r _ user1 nice1 system1 idle1 iowait1 irq1 softirq1 steal1 guest1 guest_nice1 < /proc/stat
  sleep 1
  local user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 guest2 guest_nice2
  read -r _ user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 guest2 guest_nice2 < /proc/stat
  local idle_delta=$((idle2 - idle1))
  local total1=$((user1 + nice1 + system1 + idle1 + iowait1 + irq1 + softirq1 + steal1))
  local total2=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2))
  local total_delta=$((total2 - total1))
  local usage=$(( (1000 * (total_delta - idle_delta) / total_delta + 5) / 10 ))
  echo "$usage"
}

# 函数: 采集内存使用信息
collect_mem() {
  local mem_total mem_free buffers cached
  mem_total=$(grep -i '^MemTotal:' /proc/meminfo | awk '{print $2}')
  mem_free=$(grep -i '^MemFree:' /proc/meminfo | awk '{print $2}')
  buffers=$(grep -i '^Buffers:' /proc/meminfo | awk '{print $2}')
  cached=$(grep -i '^Cached:' /proc/meminfo | awk '{print $2}')
  local used=$((mem_total - mem_free - buffers - cached))
  echo "{\"total_kb\":$mem_total,\"used_kb\":$used}"
}

# 函数: 采集磁盘空间使用
collect_disk() {
  df -P -k | awk 'NR>1 {printf("{\"fs\":\"%s\",\"mount\":\"%s\",\"total_kb\":%d,\"used_kb\":%d,\"avail_kb\":%d}\n",$1,$6,$2,$3,$4)}'
}

# 函数: 采集负载信息
collect_load() {
  awk '{printf("{\"load1\":%s,\"load5\":%s,\"load15\":%s}\n",$1,$2,$3)}' /proc/loadavg
}

# 函数: 主入口
main() {
  init_output_dir
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  local cpu mem load
  cpu=$(collect_cpu)
  mem=$(collect_mem)
  load=$(collect_load)
  local disk_json
  disk_json=$(collect_disk | paste -sd "," -)
  echo "{\"timestamp\":\"$ts\",\"cpu_pct\":$cpu,\"memory\":$mem,\"load\":$load,\"disks\":[${disk_json}]}" >> "${OUT_FILE}"
}

main "$@"

