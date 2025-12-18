#!/usr/bin/env bash
set -euo pipefail

# 函数: 构建监控项目打包文件
build_package() {
  local ROOT_DIR
  ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
  local PKG_NAME="monitor-$(date +%Y%m%d).tar.gz"
  local OUT="${ROOT_DIR}/${PKG_NAME}"
  tar -czf "$OUT" -C "${ROOT_DIR}" monitor
  echo "已生成打包文件: ${OUT}"
}

build_package "$@"

