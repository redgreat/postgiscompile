#!/bin/bash
# PostgreSQL 软 RAID 存储搭建：mdadm RAID10 数据盘 + 可选 WAL 分盘
# 建议先运行 storage_plan.sh 确认方案，再执行本脚本

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
echo_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_err()   { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=storage_common.sh
source "${SCRIPT_DIR}/storage_common.sh"

OUT_DIR="${INSTALLER_DIR}/docs"
TS="$(date +'%Y%m%d_%H%M%S')"
OUT_FILE=""

STORAGE_PG_DATA_DIR="${PG_DATA_DIR:-/opt/postgresql/data}"
STORAGE_PG_WAL_DIR="${PG_WAL_DIR:-}"
STORAGE_LAYOUT_MODE="auto"
STORAGE_DISK_LIST=()
STORAGE_OS_DISK=""
STORAGE_FORCE=false
STORAGE_DRY_RUN=false
STORAGE_DATA_MD=""
STORAGE_WAL_MD=""

DATA_DISKS=()
WAL_DISKS=()
DATA_MOUNT=""
WAL_MOUNT=""

usage() {
  cat <<'EOF'
PostgreSQL 软 RAID 存储搭建（破坏性操作：清空指定磁盘并创建阵列）

用法:
  sudo bash bin/storage_setup.sh [选项]

选项:
  --pg-data-dir PATH    PostgreSQL 数据目录 (默认: /opt/postgresql/data)
  --pg-wal-dir PATH     WAL 目录 (分盘布局默认: /pgwal)
  --layout MODE         4all | 6split | 8split | 8wal-raid10 | auto (默认)
  --disk DEV [...]      成员磁盘列表 (不指定则自动检测空闲盘)
  --os-disk DEV         排除系统盘 (可多次)
  --data-md DEV         数据阵列设备 (默认: 自动选取空闲 /dev/mdN)
  --wal-md DEV          WAL 阵列设备 (默认: 自动选取)
  --output FILE         搭建报告路径
  --dry-run             仅打印将执行的步骤，不写盘
  --yes                 跳过交互确认 (仍建议先 dry-run)
  -h, --help            显示帮助

推荐流程:
  1. sudo bash bin/storage_plan.sh --layout 4all --yes
  2. sudo bash bin/storage_setup.sh --layout 4all --dry-run
  3. sudo bash bin/storage_setup.sh --layout 4all --yes
  4. sudo bash bin/storage_verify.sh
  5. sudo bash bin/preinstall_report.sh
  6. sudo bash bin/install.sh

EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pg-data-dir)   STORAGE_PG_DATA_DIR="$2"; shift 2 ;;
    --pg-wal-dir)    STORAGE_PG_WAL_DIR="$2"; shift 2 ;;
    --layout)        STORAGE_LAYOUT_MODE="$2"; shift 2 ;;
    --disk)
      shift
      while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
        STORAGE_DISK_LIST+=("$1")
        shift
      done
      ;;
    --os-disk)       STORAGE_OS_DISK="${STORAGE_OS_DISK} $2"; shift 2 ;;
    --data-md)       STORAGE_DATA_MD="$2"; shift 2 ;;
    --wal-md)        STORAGE_WAL_MD="$2"; shift 2 ;;
    --output)        OUT_FILE="$2"; shift 2 ;;
    --dry-run)       STORAGE_DRY_RUN=true; shift ;;
    --yes|-y)        STORAGE_FORCE=true; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               echo_err "未知参数: $1"; usage; exit 1 ;;
  esac
done

run_cmd() {
  if [ "$STORAGE_DRY_RUN" = true ]; then
    echo_info "[dry-run] $*"
  else
    echo_info "$*"
    "$@"
  fi
}

append_report() { printf '%s\n' "$1" >> "$OUT_FILE"; }

find_free_md() {
  local n=0
  while [ -e "/dev/md${n}" ] || grep -q "md${n}" /proc/mdstat 2>/dev/null; do
    n=$((n + 1))
  done
  echo "/dev/md${n}"
}

next_md_after() {
  local base="$1"
  local n="${base#/dev/md}"
  n=$((n + 1))
  while [ -e "/dev/md${n}" ] || grep -q "md${n}" /proc/mdstat 2>/dev/null; do
    n=$((n + 1))
  done
  echo "/dev/md${n}"
}

ensure_packages() {
  local missing=()
  command -v mdadm >/dev/null 2>&1 || missing+=(mdadm)
  command -v mkfs.xfs >/dev/null 2>&1 || missing+=(xfsprogs)
  if [ ${#missing[@]} -eq 0 ]; then
    return 0
  fi
  echo_info "安装依赖: ${missing[*]}"
  if [ "$STORAGE_DRY_RUN" = true ]; then
    echo_info "[dry-run] dnf install -y ${missing[*]}"
    return 0
  fi
  if command -v dnf >/dev/null 2>&1; then
    dnf -y install "${missing[@]}" || {
      echo_err "无法安装 ${missing[*]}，请离线环境中预先安装 mdadm、xfsprogs"
      exit 1
    }
  else
    echo_err "缺少命令: ${missing[*]}"
    exit 1
  fi
}

validate_disk_for_raid() {
  local disk="$1"
  disk="$(storage_norm_disk "$disk")"
  if storage_disk_in_list "$disk" $STORAGE_OS_DISK; then
    echo_err "磁盘 ${disk} 被识别为系统盘，拒绝使用"
    exit 1
  fi
  if findmnt -S "$disk" >/dev/null 2>&1; then
    echo_err "磁盘 ${disk} 或其分区已挂载"
    exit 1
  fi
  if lsblk -ln -o MOUNTPOINT "$disk" 2>/dev/null | grep -q '/'; then
    echo_err "磁盘 ${disk} 存在已挂载分区"
    exit 1
  fi
}

confirm_destroy() {
  if [ "$STORAGE_FORCE" = true ] || [ "$STORAGE_DRY_RUN" = true ]; then
    return 0
  fi
  echo_warn "以下磁盘将被清空并用于 RAID，数据不可恢复:"
  printf '  %s\n' "${DATA_DISKS[@]}"
  if [ ${#WAL_DISKS[@]} -gt 0 ]; then
    echo_warn "WAL 成员盘:"
    printf '  %s\n' "${WAL_DISKS[@]}"
  fi
  echo ""
  echo -n "输入 DESTROY 确认继续: "
  read -r ans
  [ "$ans" = "DESTROY" ] || { echo_info "已取消"; exit 0; }
}

wipe_disk() {
  local disk="$1"
  run_cmd wipefs -a "$disk"
  if [ "$STORAGE_DRY_RUN" != true ]; then
    # 清除旧分区表
    printf 'o\nw\n' | fdisk "$disk" >/dev/null 2>&1 || true
  fi
}

create_md_array() {
  local md_dev="$1"
  local level="$2"
  shift 2
  local disks=("$@")
  local n=${#disks[@]}
  local i
  for i in "${disks[@]}"; do
    wipe_disk "$i"
  done
  run_cmd mdadm --create "$md_dev" --level="$level" --raid-devices="$n" "${disks[@]}"
  if [ "$STORAGE_DRY_RUN" != true ]; then
    run_cmd mdadm --wait "$md_dev" || true
  fi
}

format_and_mount() {
  local md_dev="$1"
  local mount_point="$2"
  run_cmd mkfs.xfs -f "$md_dev"
  run_cmd mkdir -p "$mount_point"
  if findmnt "$mount_point" >/dev/null 2>&1; then
    echo_warn "挂载点 ${mount_point} 已挂载，跳过 mount"
  else
    run_cmd mount -o noatime "$md_dev" "$mount_point"
  fi
  if [ "$STORAGE_DRY_RUN" != true ]; then
    if ! grep -qF "$mount_point" /etc/fstab 2>/dev/null; then
      local uuid
      uuid=$(blkid -s UUID -o value "$md_dev")
      echo "UUID=${uuid}  ${mount_point}  xfs  defaults,noatime  0 0" >> /etc/fstab
      echo_ok "已写入 /etc/fstab: ${mount_point}"
    fi
  else
    echo_info "[dry-run] 写入 /etc/fstab UUID=... ${mount_point} xfs defaults,noatime"
  fi
}

persist_mdadm() {
  if [ "$STORAGE_DRY_RUN" = true ]; then
    echo_info "[dry-run] mdadm --detail --scan >> /etc/mdadm.conf"
    return 0
  fi
  mkdir -p /etc/mdadm
  if [ -f /etc/mdadm.conf ]; then
    cp -a /etc/mdadm.conf "/etc/mdadm.conf.bak.${TS}"
  fi
  mdadm --detail --scan >> /etc/mdadm.conf 2>/dev/null || true
  if [ -f /etc/mdadm/mdadm.conf ]; then
    mdadm --detail --scan >> /etc/mdadm/mdadm.conf 2>/dev/null || true
  fi
  if command -v dracut >/dev/null 2>&1; then
    dracut -H -f /boot/initramfs-$(uname -r).img "$(uname -r)" 2>/dev/null || \
      echo_warn "initramfs 重建失败，请手动 dracut 以确保阵列引导"
  fi
  systemctl enable mdmonitor.service 2>/dev/null || true
}

write_storage_env() {
  local env_file="/etc/postgiscompile/storage.env"
  if [ "$STORAGE_DRY_RUN" = true ]; then
    echo_info "[dry-run] 写入 ${env_file}"
    return 0
  fi
  mkdir -p /etc/postgiscompile
  cat > "$env_file" <<EOF
# 由 bin/storage_setup.sh 生成 — install.sh 将自动读取
PG_DATA_DIR=${STORAGE_PG_DATA_DIR}
PG_DATA_MOUNT=${DATA_MOUNT}
PG_WAL_DIR=${STORAGE_PG_WAL_DIR}
PG_STORAGE_LAYOUT=${STORAGE_LAYOUT_MODE}
STORAGE_MEDIA=hdd
EOF
  chmod 644 "$env_file"
  echo_ok "已写入 ${env_file}"
}

prepare_layout() {
  storage_collect_disks
  if [ "$(storage_count_disks)" -eq 0 ]; then
    echo_err "未检测到可用磁盘，请使用 --disk 指定"
    exit 1
  fi
  if [ "$STORAGE_LAYOUT_MODE" = "auto" ]; then
    STORAGE_LAYOUT_MODE=$(storage_auto_layout)
    echo_info "自动选择布局: ${STORAGE_LAYOUT_MODE}"
  fi
  if ! storage_resolve_layout; then
    echo_err "无效布局: ${STORAGE_LAYOUT_MODE}"
    exit 1
  fi
  local req n
  req=$(storage_required_disk_count "$STORAGE_LAYOUT_MODE")
  n=$(storage_count_disks)
  if [ "$n" -lt "$req" ]; then
    echo_err "布局 ${STORAGE_LAYOUT_MODE} 需要至少 ${req} 块盘，当前 ${n} 块"
    exit 1
  fi
  storage_resolve_wal_dir
  mapfile -t DATA_DISKS < <(storage_layout_disks data "$STORAGE_LAYOUT_MODE")
  mapfile -t WAL_DISKS < <(storage_layout_disks wal "$STORAGE_LAYOUT_MODE")
  DATA_MOUNT="$(storage_data_mount_point)"
  if storage_wal_separate; then
    WAL_MOUNT="$STORAGE_PG_WAL_DIR"
  fi
  [ -z "$STORAGE_DATA_MD" ] && STORAGE_DATA_MD="$(find_free_md)"
  if storage_wal_separate; then
    [ -z "$STORAGE_WAL_MD" ] && STORAGE_WAL_MD="$(next_md_after "$STORAGE_DATA_MD")"
  fi
}

write_report() {
  if [ -z "$OUT_FILE" ]; then
    mkdir -p "$OUT_DIR" 2>/dev/null || true
    OUT_FILE="${OUT_DIR}/storage_setup_${TS}.md"
  fi
  : > "$OUT_FILE"
  append_report "# PostgreSQL 存储搭建报告"
  append_report ""
  append_report "- 时间: $(date +'%Y-%m-%d %H:%M:%S')"
  append_report "- 布局: \`${STORAGE_LAYOUT_MODE}\`"
  append_report "- 数据阵列: \`${STORAGE_DATA_MD}\` -> \`${DATA_MOUNT}\`"
  append_report "- 数据目录: \`${STORAGE_PG_DATA_DIR}\`"
  if storage_wal_separate; then
    append_report "- WAL 阵列: \`${STORAGE_WAL_MD}\` -> \`${WAL_MOUNT}\`"
  else
    append_report "- WAL: 与数据同卷 \`${STORAGE_PG_WAL_DIR}\`"
  fi
  append_report "- dry-run: ${STORAGE_DRY_RUN}"
  append_report ""
  append_report "## 成员盘"
  append_report "- 数据: \`${DATA_DISKS[*]}\`"
  [ ${#WAL_DISKS[@]} -gt 0 ] && append_report "- WAL: \`${WAL_DISKS[*]}\`"
  append_report ""
  append_report "## 下一步"
  append_report "1. \`sudo bash bin/storage_verify.sh\` — 存储验收"
  append_report "2. \`sudo bash bin/preinstall_report.sh\` — fio 验证"
  append_report "3. \`sudo bash bin/install.sh\` — 安装 PostgreSQL（自动读取 /etc/postgiscompile/storage.env）"
  if storage_wal_separate; then
    append_report "4. initdb 将使用 \`--waldir=${STORAGE_PG_WAL_DIR}\`"
  fi
}

main() {
  if [ "$(id -u)" -ne 0 ]; then
    echo_err "请使用 root 运行: sudo bash bin/storage_setup.sh"
    exit 1
  fi

  prepare_layout
  local d
  for d in "${DATA_DISKS[@]}" "${WAL_DISKS[@]}"; do
    validate_disk_for_raid "$d"
  done

  echo ""
  echo_info "布局: ${STORAGE_LAYOUT_MODE}"
  echo_info "数据: ${STORAGE_DATA_MD} (RAID10) <- ${DATA_DISKS[*]}"
  echo_info "挂载: ${DATA_MOUNT} -> ${STORAGE_PG_DATA_DIR}"
  if storage_wal_separate; then
    local wl
    wl=$(storage_raid_level_for_role wal)
    echo_info "WAL:  ${STORAGE_WAL_MD} (RAID${wl}) <- ${WAL_DISKS[*]}"
    echo_info "挂载: ${WAL_MOUNT}"
  fi
  echo ""

  confirm_destroy
  ensure_packages

  create_md_array "$STORAGE_DATA_MD" 10 "${DATA_DISKS[@]}"
  format_and_mount "$STORAGE_DATA_MD" "$DATA_MOUNT"

  if storage_wal_separate; then
    local wal_level
    wal_level=$(storage_raid_level_for_role wal)
    create_md_array "$STORAGE_WAL_MD" "$wal_level" "${WAL_DISKS[@]}"
    format_and_mount "$STORAGE_WAL_MD" "$WAL_MOUNT"
  fi

  if [ "$STORAGE_DRY_RUN" != true ]; then
    run_cmd mkdir -p "$STORAGE_PG_DATA_DIR"
    if id postgres >/dev/null 2>&1; then
      chown postgres:postgres "$DATA_MOUNT" "$STORAGE_PG_DATA_DIR"
      chmod 700 "$STORAGE_PG_DATA_DIR"
      if storage_wal_separate; then
        chown postgres:postgres "$WAL_MOUNT"
      fi
    fi
  else
    echo_info "[dry-run] mkdir -p ${STORAGE_PG_DATA_DIR} && chown postgres"
  fi

  persist_mdadm
  write_storage_env
  write_report

  echo ""
  echo_ok "存储搭建完成"
  echo_info "报告: ${OUT_FILE}"
  echo_info "后续: bin/preinstall_report.sh -> bin/install.sh"
  echo ""
}

main
