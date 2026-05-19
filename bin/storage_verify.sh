#!/bin/bash
# PostgreSQL 存储验收：mdadm 阵列、挂载、fstab、目录权限
# 建议在 storage_setup 之后、install.sh 之前/之后各执行一次

set -u
if [ -n "${BASH_VERSION:-}" ]; then
  set -o pipefail 2>/dev/null || true
fi
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_ok()    { echo -e "${GREEN}[PASS]${NC} $1"; }
echo_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_fail()  { echo -e "${RED}[FAIL]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=storage_common.sh
source "${SCRIPT_DIR}/storage_common.sh"

OUT_DIR="${INSTALLER_DIR}/docs"
TS="$(date +'%Y%m%d_%H%M%S')"
OUT_FILE=""
STRICT=false

STORAGE_PG_DATA_DIR="${PG_DATA_DIR:-/opt/postgresql/data}"
STORAGE_PG_WAL_DIR=""
STORAGE_LAYOUT_MODE=""
PG_DATA_MOUNT=""
PG_WAL_SEPARATE=false

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

usage() {
  cat <<'EOF'
PostgreSQL 存储验收检查

用法:
  sudo bash bin/storage_verify.sh [选项]

选项:
  --pg-data-dir PATH   数据目录 (默认: /etc/postgiscompile/storage.env 或 /opt/postgresql/data)
  --pg-wal-dir PATH    WAL 目录 (默认: 从 storage.env 读取)
  --layout MODE        期望布局: 4all | 6split (用于校验 WAL 是否应独立)
  --output FILE        Markdown 报告路径
  --strict             将 WARN 视为失败 (退出码 1)
  -h, --help           显示帮助

说明:
  - 优先读取 /etc/postgiscompile/storage.env（由 storage_setup.sh 生成）
  - 退出码: 0=无 FAIL；1=存在 FAIL 或 --strict 下存在 WARN

EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pg-data-dir) STORAGE_PG_DATA_DIR="$2"; shift 2 ;;
    --pg-wal-dir)  STORAGE_PG_WAL_DIR="$2"; shift 2 ;;
    --layout)      STORAGE_LAYOUT_MODE="$2"; shift 2 ;;
    --output)      OUT_FILE="$2"; shift 2 ;;
    --strict)      STRICT=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             echo_fail "未知参数: $1"; usage; exit 1 ;;
  esac
done

load_env() {
  local env_file="/etc/postgiscompile/storage.env"
  if [ -f "$env_file" ]; then
    # shellcheck disable=SC1090
    source "$env_file"
    STORAGE_PG_DATA_DIR="${PG_DATA_DIR:-$STORAGE_PG_DATA_DIR}"
    STORAGE_PG_WAL_DIR="${PG_WAL_DIR:-$STORAGE_PG_WAL_DIR}"
    PG_DATA_MOUNT="${PG_DATA_MOUNT:-$(dirname "$STORAGE_PG_DATA_DIR")}"
    STORAGE_LAYOUT_MODE="${PG_STORAGE_LAYOUT:-$STORAGE_LAYOUT_MODE}"
    echo_info "已加载 ${env_file}"
  else
    PG_DATA_MOUNT="$(dirname "$STORAGE_PG_DATA_DIR")"
    echo_warn "未找到 ${env_file}，使用命令行/默认路径"
  fi
  if [ -z "$STORAGE_PG_WAL_DIR" ]; then
    STORAGE_PG_WAL_DIR="${STORAGE_PG_DATA_DIR}/pg_wal"
  fi
  case "$STORAGE_LAYOUT_MODE" in
    6split|8split|8wal-raid10) PG_WAL_SEPARATE=true ;;
    4all|"") PG_WAL_SEPARATE=false ;;
  esac
  if [ -n "$STORAGE_LAYOUT_MODE" ] && [ "$STORAGE_LAYOUT_MODE" != "4all" ]; then
    PG_WAL_SEPARATE=true
  fi
}

record_pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo_ok "$1"; append_report "| ✅ | $1 |"; }
record_warn() { WARN_COUNT=$((WARN_COUNT + 1)); echo_warn "$1"; append_report "| ⚠️ | $1 |"; }
record_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo_fail "$1"; append_report "| ❌ | $1 |"; }

append_report() { printf '%s\n' "$1" >> "$OUT_FILE"; }

init_report() {
  if [ -z "$OUT_FILE" ]; then
    mkdir -p "$OUT_DIR" 2>/dev/null || true
    OUT_FILE="${OUT_DIR}/storage_verify_${TS}.md"
    if ! touch "$OUT_FILE" 2>/dev/null; then
      OUT_FILE="/tmp/storage_verify_${TS}.md"
      touch "$OUT_FILE" 2>/dev/null || true
    fi
  fi
  : > "$OUT_FILE"
  append_report "# PostgreSQL 存储验收报告"
  append_report ""
  append_report "- 时间: $(date +'%Y-%m-%d %H:%M:%S')"
  append_report "- 数据目录: \`${STORAGE_PG_DATA_DIR}\`"
  append_report "- 数据挂载点: \`${PG_DATA_MOUNT}\`"
  append_report "- WAL 目录: \`${STORAGE_PG_WAL_DIR}\`"
  append_report "- 期望布局: \`${STORAGE_LAYOUT_MODE:-未指定}\`"
  append_report ""
  append_report "## 检查结果"
  append_report ""
  append_report "| 状态 | 说明 |"
  append_report "|------|------|"
}

check_command() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    record_pass "命令可用: ${cmd}"
  else
    record_fail "缺少命令: ${cmd}"
  fi
}

# 从挂载点解析底层块设备 (md/X)
mount_source_device() {
  findmnt -n -o SOURCE "$1" 2>/dev/null | head -1
}

check_md_device() {
  local md_dev="$1"
  local label="$2"
  local detail state active raid level

  if [ ! -b "$md_dev" ]; then
    record_fail "${label}: 设备不存在 ${md_dev}"
    return
  fi

  if ! detail=$(mdadm --detail "$md_dev" 2>/dev/null); then
    record_fail "${label}: 无法读取 mdadm 详情 ${md_dev}"
    return
  fi

  state=$(echo "$detail" | awk -F': ' '/State/ {print $2; exit}')
  active=$(echo "$detail" | awk -F': ' '/Active Devices/ {print $2; exit}')
  raid=$(echo "$detail" | awk -F': ' '/Raid Level/ {print $2; exit}')
  level=$(echo "$raid" | awk '{print $1}')

  if echo "$state" | grep -qiE 'clean|active'; then
    record_pass "${label}: ${md_dev} 状态正常 (${state})"
  elif echo "$state" | grep -qi degraded; then
    record_fail "${label}: ${md_dev} 阵列降级 (${state})"
  else
    record_warn "${label}: ${md_dev} 状态: ${state:-未知}"
  fi

  if echo "$detail" | grep -qi 'failed'; then
    record_fail "${label}: ${md_dev} 存在 failed 成员盘"
  fi

  append_report ""
  append_report "### ${label} — \`${md_dev}\`"
  append_report "\`\`\`"
  echo "$detail" >> "$OUT_FILE"
  append_report "\`\`\`"
}

# 成功时写入 VERIFY_MOUNT_SRC
VERIFY_MOUNT_SRC=""

check_mount() {
  local mnt="$1"
  local label="$2"
  local expect_fs="${3:-xfs}"
  local src fstype opts

  VERIFY_MOUNT_SRC=""
  if [ ! -d "$mnt" ]; then
    record_fail "${label}: 挂载点目录不存在 ${mnt}"
    return 1
  fi

  if ! findmnt "$mnt" >/dev/null 2>&1; then
    record_fail "${label}: 未挂载 ${mnt}"
    return 1
  fi

  src=$(mount_source_device "$mnt")
  VERIFY_MOUNT_SRC="$src"
  fstype=$(findmnt -n -o FSTYPE "$mnt" 2>/dev/null)
  opts=$(findmnt -n -o OPTIONS "$mnt" 2>/dev/null)

  record_pass "${label}: ${mnt} 已挂载 <- ${src} (${fstype})"

  if [ "$fstype" = "$expect_fs" ]; then
    record_pass "${label}: 文件系统为 ${fstype}"
  else
    record_warn "${label}: 文件系统为 ${fstype}，期望 ${expect_fs}"
  fi

  if echo "$opts" | grep -q noatime; then
    record_pass "${label}: 挂载选项含 noatime"
  else
    record_warn "${label}: 挂载选项未含 noatime (${opts})"
  fi

  if [[ "$src" == /dev/md* ]] || [[ "$src" == /dev/mapper/* ]]; then
    record_pass "${label}: 源设备为块阵列/映射设备"
  else
    record_warn "${label}: 源设备非 md (${src})"
  fi

  return 0
}

check_fstab_entry() {
  local mnt="$1"
  local label="$2"

  if [ ! -f /etc/fstab ]; then
    record_fail "缺少 /etc/fstab"
    return
  fi

  if grep -qE "[[:space:]]${mnt}[[:space:]]" /etc/fstab 2>/dev/null; then
    record_pass "${label}: /etc/fstab 含 ${mnt} 条目"
    local line
    line=$(grep -E "[[:space:]]${mnt}[[:space:]]" /etc/fstab | head -1)
    if echo "$line" | grep -qE '^UUID='; then
      record_pass "${label}: fstab 使用 UUID"
    else
      record_warn "${label}: fstab 未使用 UUID: ${line}"
    fi
  else
    record_fail "${label}: /etc/fstab 缺少 ${mnt}"
  fi
}

check_dir_permissions() {
  local dir="$1"
  local label="$2"
  local expect_owner="${3:-postgres:postgres}"
  local expect_mode="${4:-700}"

  if [ ! -d "$dir" ]; then
    record_warn "${label}: 目录不存在 ${dir}（install 前可为正常）"
    return
  fi

  local owner mode
  owner=$(stat -c '%U:%G' "$dir" 2>/dev/null || echo "?")
  mode=$(stat -c '%a' "$dir" 2>/dev/null || echo "?")

  if [ "$owner" = "$expect_owner" ]; then
    record_pass "${label}: 属主 ${owner}"
  elif ! id postgres >/dev/null 2>&1; then
    record_warn "${label}: 属主 ${owner}（postgres 用户尚未创建）"
  else
    record_fail "${label}: 属主 ${owner}，期望 ${expect_owner}"
  fi

  if [ "$mode" = "$expect_mode" ]; then
    record_pass "${label}: 权限 ${mode}"
  else
    record_warn "${label}: 权限 ${mode}，期望 ${expect_mode}"
  fi
}

check_wal_layout() {
  if [ "$PG_WAL_SEPARATE" = true ]; then
    if [ "$STORAGE_PG_WAL_DIR" = "${STORAGE_PG_DATA_DIR}/pg_wal" ]; then
      record_fail "布局要求 WAL 独立，但 WAL 路径仍在数据目录内"
    fi
    if [ -d "$STORAGE_PG_DATA_DIR" ] && [ -d "${STORAGE_PG_DATA_DIR}/pg_wal" ] && [ ! -L "${STORAGE_PG_DATA_DIR}/pg_wal" ]; then
      if findmnt "${STORAGE_PG_DATA_DIR}/pg_wal" >/dev/null 2>&1; then
        record_warn "数据目录内仍有 pg_wal 且已挂载，请确认是否已迁移到独立卷"
      fi
    fi
    if check_mount "$STORAGE_PG_WAL_DIR" "WAL 卷" xfs; then
      if [ -n "${VERIFY_MOUNT_SRC:-}" ] && [[ "$VERIFY_MOUNT_SRC" == /dev/md* ]]; then
        check_md_device "$VERIFY_MOUNT_SRC" "WAL 阵列"
      fi
    fi
    check_fstab_entry "$STORAGE_PG_WAL_DIR" "WAL"
    check_dir_permissions "$STORAGE_PG_WAL_DIR" "WAL 目录"
  else
    if findmnt "$STORAGE_PG_WAL_DIR" >/dev/null 2>&1 && [ "$STORAGE_PG_WAL_DIR" != "${STORAGE_PG_DATA_DIR}/pg_wal" ]; then
      record_warn "4all 布局下 WAL 路径 ${STORAGE_PG_WAL_DIR} 为独立挂载，与预期不符"
    else
      record_pass "WAL 与数据同卷 (4all)"
    fi
  fi
}

check_disk_space() {
  local mnt="$1"
  local label="$2"
  local avail_pct avail
  if ! findmnt "$mnt" >/dev/null 2>&1; then
    return
  fi
  avail_pct=$(df -P "$mnt" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
  avail=$(df -hP "$mnt" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$avail_pct" ] && [ "$avail_pct" -ge 95 ]; then
    record_fail "${label}: 空间不足，已用 ${avail_pct}%"
  elif [ -n "$avail_pct" ] && [ "$avail_pct" -ge 90 ]; then
    record_warn "${label}: 已用 ${avail_pct}%，可用 ${avail}"
  else
    record_pass "${label}: 可用空间 ${avail} (已用 ${avail_pct:-?}%)"
  fi
}

check_mdadm_conf() {
  local found=0
  for f in /etc/mdadm.conf /etc/mdadm/mdadm.conf; do
    if [ -f "$f" ] && grep -qE '^ARRAY' "$f" 2>/dev/null; then
      record_pass "mdadm 配置含 ARRAY 定义: ${f}"
      found=1
    fi
  done
  if [ "$found" -eq 0 ]; then
    record_warn "mdadm 配置中未找到 ARRAY 行，重启后阵列可能无法自动组装"
  fi
}

check_proc_mdstat() {
  if [ ! -f /proc/mdstat ]; then
    record_warn "无 /proc/mdstat"
    return
  fi
  append_report ""
  append_report "## /proc/mdstat"
  append_report "\`\`\`"
  cat /proc/mdstat >> "$OUT_FILE" 2>/dev/null || true
  append_report "\`\`\`"
  if grep -q '_' /proc/mdstat 2>/dev/null; then
    record_fail "mdstat 中存在降级/恢复标记 (_)"
  else
    record_pass "/proc/mdstat 无降级标记"
  fi
}

finalize_report() {
  append_report ""
  append_report "## 汇总"
  append_report ""
  append_report "| 级别 | 数量 |"
  append_report "|------|------|"
  append_report "| ✅ PASS | ${PASS_COUNT} |"
  append_report "| ⚠️ WARN | ${WARN_COUNT} |"
  append_report "| ❌ FAIL | ${FAIL_COUNT} |"
  append_report ""
  append_report "## 块设备树"
  append_report "\`\`\`"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL >> "$OUT_FILE" 2>/dev/null || true
  append_report "\`\`\`"
}

main() {
  if [ "$(id -u)" -ne 0 ]; then
    echo_warn "建议 root 运行以完整检查权限与 mdadm"
  fi

  load_env
  init_report

  check_command mdadm
  check_command findmnt
  check_command lsblk

  check_proc_mdstat
  check_mdadm_conf

  if check_mount "$PG_DATA_MOUNT" "数据卷" xfs; then
    if [ -n "${VERIFY_MOUNT_SRC:-}" ] && [[ "$VERIFY_MOUNT_SRC" == /dev/md* ]]; then
      check_md_device "$VERIFY_MOUNT_SRC" "数据阵列"
    elif [ -n "${VERIFY_MOUNT_SRC:-}" ]; then
      record_warn "数据卷源非 md 设备: ${VERIFY_MOUNT_SRC}"
    fi
  fi

  check_fstab_entry "$PG_DATA_MOUNT" "数据"
  check_disk_space "$PG_DATA_MOUNT" "数据卷"
  check_dir_permissions "$STORAGE_PG_DATA_DIR" "数据目录"

  check_wal_layout

  finalize_report

  echo ""
  echo_info "报告: ${OUT_FILE}"
  echo_info "汇总: PASS=${PASS_COUNT} WARN=${WARN_COUNT} FAIL=${FAIL_COUNT}"

  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo_fail "验收未通过"
    exit 1
  fi
  if [ "$STRICT" = true ] && [ "$WARN_COUNT" -gt 0 ]; then
    echo_warn "严格模式: 存在 WARN"
    exit 1
  fi
  echo_ok "验收通过"
  exit 0
}

main
