#!/bin/bash
# PostgreSQL 存储规划：软 RAID10 数据盘 + WAL 分盘方案（只读规划，不改动磁盘）
# 用法见: storage_plan.sh --help

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
echo_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
echo_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_err()   { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=storage_common.sh
source "${SCRIPT_DIR}/storage_common.sh"
OUT_DIR="${INSTALLER_DIR}/docs"
TS="$(date +'%Y%m%d_%H%M%S')"

PG_DATA_DIR="${PG_DATA_DIR:-/opt/postgresql/data}"
PG_WAL_DIR="${PG_WAL_DIR:-}"          # 空则规划为 ${PG_DATA_DIR}/pg_wal 或独立挂载点
OUT_FILE=""
LAYOUT_MODE="auto"                    # auto | 4all | 6split | 8split | 8wal-raid10
DISK_LIST=()                          # 用户指定的数据候选盘，如 /dev/sdb
OS_DISK=""
NON_INTERACTIVE=false

usage() {
  cat <<'EOF'
PostgreSQL 软 RAID 存储规划（仅输出方案，不创建阵列）

用法:
  sudo bash bin/storage_plan.sh [选项]

选项:
  --pg-data-dir PATH    PostgreSQL 数据目录 (默认: /opt/postgresql/data)
  --pg-wal-dir PATH     规划中的 WAL 目录 (默认: 随布局自动选择)
  --layout MODE         布局模式:
                          auto          按可用磁盘数量自动推荐 (默认)
                          4all          4 盘 RAID10 单阵列 (数据+WAL 同卷)
                          6split        4 盘 RAID10 数据 + 2 盘 RAID1 WAL
                          8split        4 盘 RAID10 数据 + 2 盘 RAID1 WAL (8 盘时推荐)
                          8wal-raid10   4 盘 RAID10 数据 + 4 盘 RAID10 WAL (高 IO 可选)
  --disk DEV [...]      仅使用列出的空闲磁盘 (如 /dev/sdb /dev/sdc)
  --os-disk DEV         视为系统盘，从候选中排除 (可多次指定)
  --output FILE         报告输出路径 (默认: docs/storage_plan_YYYYMMDD_HHMMSS.md)
  --yes                 非交互：接受 auto 布局与检测到的磁盘列表
  -h, --help            显示帮助

说明:
  - 本脚本只生成 mdadm/LVM/挂载点规划，不执行分区或 mkfs。
  - 4 块盘无法同时做「数据 RAID10」与「独立 WAL RAID10」，需 8 块盘及以上。
  - WAL 对延迟敏感、容量小；通常 2 盘 RAID1 即可，不必单独 4 盘 RAID10。

示例:
  sudo bash bin/storage_plan.sh
  sudo bash bin/storage_plan.sh --layout 6split --disk /dev/sdb /dev/sdc /dev/sdd /dev/sde /dev/sdf /dev/sdg
  sudo bash bin/storage_plan.sh --layout 4all --yes --pg-data-dir /pgdata/data
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pg-data-dir)   PG_DATA_DIR="$2"; shift 2 ;;
    --pg-wal-dir)    PG_WAL_DIR="$2"; shift 2 ;;
    --layout)        LAYOUT_MODE="$2"; shift 2 ;;
    --disk)
      shift
      while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
        DISK_LIST+=("$1")
        shift
      done
      ;;
    --os-disk)       OS_DISK="${OS_DISK} $2"; shift 2 ;;
    --output)        OUT_FILE="$2"; shift 2 ;;
    --yes|-y)        NON_INTERACTIVE=true; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               echo_err "未知参数: $1"; usage; exit 1 ;;
  esac
done

if [ "$(id -u)" -ne 0 ] && [ -z "${ALLOW_STORAGE_PLAN_USER:-}" ]; then
  echo_warn "建议 root 运行以便准确识别系统盘与 RAID 成员盘"
fi

if [ -z "$OUT_FILE" ]; then
  mkdir -p "$OUT_DIR" 2>/dev/null || true
  OUT_FILE="${OUT_DIR}/storage_plan_${TS}.md"
  if ! touch "$OUT_FILE" 2>/dev/null; then
    OUT_DIR="/tmp"
    OUT_FILE="${OUT_DIR}/storage_plan_${TS}.md"
    touch "$OUT_FILE" 2>/dev/null || true
  fi
fi

append() { printf '%s\n' "$1" >> "$OUT_FILE"; }
section() { append ""; append "## $1"; append ""; }
bullet() { append "- $1"; }

sync_storage_vars() {
  STORAGE_PG_DATA_DIR="$PG_DATA_DIR"
  STORAGE_PG_WAL_DIR="$PG_WAL_DIR"
  STORAGE_LAYOUT_MODE="$LAYOUT_MODE"
  STORAGE_DISK_LIST=("${DISK_LIST[@]}")
  STORAGE_OS_DISK="$OS_DISK"
}

sync_plan_vars() {
  PG_DATA_DIR="$STORAGE_PG_DATA_DIR"
  PG_WAL_DIR="$STORAGE_PG_WAL_DIR"
  LAYOUT_MODE="$STORAGE_LAYOUT_MODE"
  DISK_LIST=("${STORAGE_DISK_LIST[@]}")
  OS_DISK="$STORAGE_OS_DISK"
}

resolve_layout() {
  sync_storage_vars
  local n
  n=$(storage_count_disks)
  if [ "$STORAGE_LAYOUT_MODE" = "auto" ]; then
    STORAGE_LAYOUT_MODE=$(storage_auto_layout)
    echo_info "检测到 ${n} 块候选盘，自动选择布局: ${STORAGE_LAYOUT_MODE}"
  fi
  if ! storage_resolve_layout; then
    echo_err "无效布局: $STORAGE_LAYOUT_MODE"
    exit 1
  fi
  sync_plan_vars
}

write_wal_priority_section() {
  section "WAL 分盘优先级说明"
  bullet "**优先级：中高**（侧重 **延迟与隔离**，不是与数据盘相同的容量或 IOPS 需求）。"
  bullet "WAL 以顺序写 + 频繁 `fsync` 为主，与数据文件的随机读写争抢同组盘时，易出现 **提交延迟抖动**。"
  bullet "WAL **占用空间远小于数据**（活跃 WAL 通常为数 GB～数十 GB；需为 `max_wal_size`、归档与峰值留余量，一般 **几十 GB～一两百 GB** 级即可，视归档策略而定）。"
  bullet "**不必为 WAL 单独做 4 盘 RAID10**：2 盘 **RAID1** 即可满足绝大多数生产场景（冗余 + 独立磁头）。"
  bullet "仅当 WAL 生成速率极高（大量小事务写入、同步复制、极高并发提交）且已与数据分盘仍瓶颈时，再考虑 **2 盘 RAID1 换为更高转速盘** 或 **4 盘 RAID10 专用于 WAL**（需额外 4 块盘，见 8wal-raid10 布局）。"
  bullet "**仅 4 块盘时**：无法同时「4 盘数据 RAID10」+「4 盘 WAL RAID10」；可选 **4 盘合一 RAID10**，或 **2+2（数据 RAID1 + WAL RAID1）** 牺牲容量换隔离（本脚本默认 4all 为合一 RAID10）。"
  append ""
}

write_layout_section() {
  local mode="$1"
  local req n data_disks wal_disks
  req=$(storage_required_disk_count "$mode")
  n=$(storage_count_disks)

  section "推荐布局: ${mode}"
  bullet "候选磁盘数量: **${n}**（本布局建议至少 **${req}** 块）"
  if [ "$n" -lt "$req" ]; then
    bullet "⚠️ 磁盘不足：请补盘或改用 \`--layout 4all\` / 减少 WAL 独立要求。"
  fi

  sync_storage_vars
  mapfile -t data_disks < <(storage_layout_disks data "$mode")
  mapfile -t wal_disks < <(storage_layout_disks wal "$mode")
  sync_plan_vars

  append "### 数据阵列 (RAID10)"
  append ""
  if [ ${#data_disks[@]} -eq 0 ]; then
    bullet "（无）"
  else
    bullet "成员盘: \`${data_disks[*]}\`"
    bullet "mdadm 示例名: \`/dev/md0\`"
    bullet "建议文件系统: **XFS**（挂载选项: \`noatime\`）"
    bullet "挂载点: \`$(dirname "$PG_DATA_DIR")\` 或 \`${PG_DATA_DIR}\` 的父卷"
    bullet "PostgreSQL 数据目录: \`${PG_DATA_DIR}\`"
    append ""
    append "\`\`\`bash"
    append "# 创建前请确认盘内无数据；以下仅作规划参考"
    append "mdadm --create /dev/md0 --level=10 --raid-devices=${#data_disks[@]} \\"
    append "  ${data_disks[*]}"
    append "mkfs.xfs -f /dev/md0"
    append "mkdir -p $(dirname "$PG_DATA_DIR")"
    append "mount -o noatime /dev/md0 $(dirname "$PG_DATA_DIR")"
    append "\`\`\`"
  fi

  append ""
  append "### WAL"
  append ""

  case "$mode" in
    4all)
      if [ -z "$PG_WAL_DIR" ]; then
        PG_WAL_DIR="${PG_DATA_DIR}/pg_wal"
      fi
      bullet "布局: **与数据同卷**（${#data_disks[@]} 盘 RAID10 统一存储）"
      bullet "WAL 路径: \`${PG_WAL_DIR}\`（默认在数据目录内，无需单独挂载）"
      bullet "适用: 仅 4 盘、可接受 WAL 与数据 IO 共享；实现简单、容量利用率最高。"
      bullet "若后续扩容到 6+ 盘，可 \`pg_basebackup\` + 将 \`pg_wal\` 迁至独立 RAID1 挂载点。"
      ;;
    6split|8split)
      if [ -z "$PG_WAL_DIR" ]; then
        PG_WAL_DIR="/pgwal"
      fi
      bullet "布局: **独立 2 盘 RAID1**（与数据 RAID10 分离）"
      bullet "成员盘: \`${wal_disks[*]}\`"
      bullet "mdadm 示例名: \`/dev/md1\`"
      bullet "挂载点: \`${PG_WAL_DIR}\`（安装后可将数据目录内 \`pg_wal\` 设为符号链接或 initdb 时指定）"
      append ""
      append "\`\`\`bash"
      append "mdadm --create /dev/md1 --level=1 --raid-devices=2 \\"
      append "  ${wal_disks[*]}"
      append "mkfs.xfs -f /dev/md1"
      append "mkdir -p ${PG_WAL_DIR}"
      append "mount -o noatime /dev/md1 ${PG_WAL_DIR}"
      append "# 新集群: initdb 时 --waldir=${PG_WAL_DIR}"
      append "# 已有集群: 停库 -> rsync pg_wal -> 修改符号链接 -> 启动"
      append "\`\`\`"
      if [ "$mode" = "8split" ] && [ "$n" -ge 8 ]; then
        bullet "剩余 **$(( n - 6 ))** 块盘未纳入本方案：可作备份、归档、表空间或预留热备。"
      fi
      ;;
    8wal-raid10)
      if [ -z "$PG_WAL_DIR" ]; then
        PG_WAL_DIR="/pgwal"
      fi
      bullet "布局: **独立 4 盘 RAID10 专用于 WAL**（高并发提交、WAL 带宽敏感场景）"
      bullet "成员盘: \`${wal_disks[*]}\`"
      bullet "mdadm 示例名: \`/dev/md1\`"
      bullet "挂载点: \`${PG_WAL_DIR}\`"
      bullet "说明: 容量远大于 WAL 实际需求，换取 WAL 随机/fsync 路径上的并行度；**成本高于 2 盘 RAID1**，仅在实测 WAL 为瓶颈时采用。"
      append ""
      append "\`\`\`bash"
      append "mdadm --create /dev/md1 --level=10 --raid-devices=4 \\"
      append "  ${wal_disks[*]}"
      append "mkfs.xfs -f /dev/md1"
      append "mkdir -p ${PG_WAL_DIR}"
      append "mount -o noatime /dev/md1 ${PG_WAL_DIR}"
      append "\`\`\`"
      ;;
  esac
  append ""
}

write_pg_tuning_section() {
  section "PostgreSQL 配置提示（机械盘 / RAID）"
  bullet "数据与 WAL 分盘后，模板 \`config/postgresql.conf.template\` 中 SSD  oriented 参数需调整，例如:"
  append ""
  append "\`\`\`"
  append "random_page_cost = 4.0"
  append "effective_io_concurrency = 2"
  append "wal_compression = on          # CPU 充足时降低 WAL 体积"
  append "checkpoint_completion_target = 0.9"
  append "\`\`\`"
  bullet "内存加大时优先提高 \`shared_buffers\`、\`effective_cache_size\`，比块层 RAM 缓存更安全。"
  append ""
}

write_disk_inventory() {
  section "候选磁盘清单"
  local d size model
  for d in "${DISK_LIST[@]}"; do
    size=$(lsblk -dn -o SIZE "$d" 2>/dev/null | head -1)
    model=$(lsblk -dn -o MODEL "$d" 2>/dev/null | head -1)
    bullet "\`${d}\` — ${size:-?} — ${model:-?}"
  done
  if [ -n "$(echo "$OS_DISK" | tr -s ' ')" ]; then
    append ""
    bullet "已排除系统相关盘:${OS_DISK}"
  fi
  append ""
  append "\`\`\`"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL "${DISK_LIST[@]}" 2>/dev/null >> "$OUT_FILE" || true
  append "\`\`\`"
}

write_summary_table() {
  section "布局对照速查"
  append "| 盘数 | 推荐模式 | 数据 | WAL | 说明 |"
  append "|------|----------|------|-----|------|"
  append "| 4 | \`4all\` | RAID10 ×4 | 同卷 | 无法同时双 RAID10 |"
  append "| 6 | \`6split\` | RAID10 ×4 | RAID1 ×2 | **WAL 分盘性价比最高** |"
  append "| 8 | \`8split\` | RAID10 ×4 | RAID1 ×2 | 余盘做备份/归档；**不必 WAL RAID10** |"
  append "| 8 | \`8wal-raid10\` | RAID10 ×4 | RAID10 ×4 | 仅 WAL 瓶颈明确时 |"
  append ""
}

main() {
  sync_storage_vars
  storage_collect_disks
  sync_plan_vars
  if [ "$(storage_count_disks)" -eq 0 ]; then
    echo_err "未检测到可用磁盘。请用 --disk 指定，或确认盘未挂载系统分区。"
    exit 1
  fi

  resolve_layout
  req=$(storage_required_disk_count "$LAYOUT_MODE")
  n=$(storage_count_disks)

  if [ "$n" -lt "$req" ] && [ "$NON_INTERACTIVE" != true ]; then
    echo_warn "当前 ${n} 块盘，布局 ${LAYOUT_MODE} 建议 ${req} 块。"
    echo -n "是否仍按 ${LAYOUT_MODE} 生成规划? [y/N] "
    read -r ans
    case "$ans" in
      y|Y|yes|YES) ;;
      *) echo_info "已取消"; exit 0 ;;
    esac
  fi

  : > "$OUT_FILE"
  append "# PostgreSQL 存储规划报告"
  append ""
  append "- 生成时间: $(date +'%Y-%m-%d %H:%M:%S')"
  append "- 布局模式: \`${LAYOUT_MODE}\`"
  append "- 数据目录: \`${PG_DATA_DIR}\`"
  append ""

  write_wal_priority_section
  write_summary_table
  write_disk_inventory
  write_layout_section "$LAYOUT_MODE"
  write_pg_tuning_section

  append "---"
  append ""
  append "> 下一步: \`storage_setup.sh\` → \`storage_verify.sh\` → \`preinstall_report.sh\` → \`install.sh\`（详见 README.md）"

  echo ""
  echo_ok "规划报告已生成: ${OUT_FILE}"
  echo ""
  echo_info "关于您的问题「WAL 需求级别是否高、是否单独 RAID10」:"
  echo "  - WAL 对 **延迟/隔离** 要求高，对 **容量与 RAID10 级 IOPS** 要求相对较低。"
  echo "  - **4 盘全做业务 RAID10 时**：WAL 与数据同卷即可，是常见且合理选择。"
  echo "  - **若坚持 WAL 物理分离**：至少再加 **2 盘 RAID1**（共 6 盘），不必 4 盘 RAID10 专供 WAL。"
  echo "  - **仅当 WAL 实测为瓶颈** 且客户能再提供 4 盘时，再考虑 \`--layout 8wal-raid10\`。"
  echo ""
}

main
