# shellcheck shell=bash
# PostgreSQL 软 RAID 存储规划/搭建 — 公共函数（由 storage_plan.sh / storage_setup.sh source）

storage_norm_disk() {
  local d="$1"
  d="${d#/dev/}"
  echo "/dev/${d%%[0-9]*}"
}

storage_disk_in_list() {
  local needle="$1"
  shift
  local x
  for x in "$@"; do
    [ "$(storage_norm_disk "$x")" = "$(storage_norm_disk "$needle")" ] && return 0
  done
  return 1
}

storage_detect_os_disks() {
  local root_src pk dev
  root_src=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
  [ -z "$root_src" ] && return 0
  pk=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -1)
  if [ -n "$pk" ]; then
    STORAGE_OS_DISK="${STORAGE_OS_DISK} $(storage_norm_disk "/dev/${pk}")"
  fi
  dev="$root_src"
  while [ -n "$dev" ]; do
    pk=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1)
    [ -z "$pk" ] && break
    STORAGE_OS_DISK="${STORAGE_OS_DISK} $(storage_norm_disk "/dev/${pk}")"
    dev="/dev/${pk}"
  done
}

storage_list_candidate_disks() {
  local name size type model dev
  while read -r name size type model; do
    [ "$type" != "disk" ] && continue
    dev="/dev/${name}"
    storage_disk_in_list "$dev" $STORAGE_OS_DISK && continue
    if lsblk -ln -o MOUNTPOINT "$dev" 2>/dev/null | grep -qE '^/$|^/boot'; then
      continue
    fi
    echo "$dev|$size|${model:-unknown}"
  done < <(lsblk -dn -o NAME,SIZE,TYPE,MODEL 2>/dev/null)
}

storage_collect_disks() {
  storage_detect_os_disks
  if [ ${#STORAGE_DISK_LIST[@]} -eq 0 ]; then
    local dev
    while IFS='|' read -r dev _ _; do
      [ -z "$dev" ] && continue
      STORAGE_DISK_LIST+=("$dev")
    done < <(storage_list_candidate_disks)
  else
    local d normed=()
    for d in "${STORAGE_DISK_LIST[@]}"; do
      normed+=("$(storage_norm_disk "$d")")
    done
    STORAGE_DISK_LIST=("${normed[@]}")
  fi
}

storage_count_disks() { echo "${#STORAGE_DISK_LIST[@]}"; }

storage_auto_layout() {
  local n
  n=$(storage_count_disks)
  case "$n" in
    4) echo "4all" ;;
    5|6) echo "6split" ;;
    7|8) echo "8split" ;;
    *) echo "4all" ;;
  esac
}

storage_resolve_layout() {
  local n
  n=$(storage_count_disks)
  if [ "$STORAGE_LAYOUT_MODE" = "auto" ]; then
    STORAGE_LAYOUT_MODE=$(storage_auto_layout)
  fi
  case "$STORAGE_LAYOUT_MODE" in
    4all|6split|8split|8wal-raid10) ;;
    *) return 1 ;;
  esac
  return 0
}

storage_layout_disks() {
  local role="$1"
  local mode="$2"
  case "$mode" in
    4all)
      [ "$role" = "data" ] && printf '%s\n' "${STORAGE_DISK_LIST[@]}"
      ;;
    6split|8split)
      if [ "$role" = "data" ]; then
        printf '%s\n' "${STORAGE_DISK_LIST[@]:0:4}"
      else
        printf '%s\n' "${STORAGE_DISK_LIST[@]:4:2}"
      fi
      ;;
    8wal-raid10)
      if [ "$role" = "data" ]; then
        printf '%s\n' "${STORAGE_DISK_LIST[@]:0:4}"
      else
        printf '%s\n' "${STORAGE_DISK_LIST[@]:4:4}"
      fi
      ;;
  esac
}

storage_required_disk_count() {
  case "$1" in
    4all) echo 4 ;;
    6split) echo 6 ;;
    8split) echo 6 ;;
    8wal-raid10) echo 8 ;;
    *) echo 4 ;;
  esac
}

storage_resolve_wal_dir() {
  case "$STORAGE_LAYOUT_MODE" in
    4all)
      [ -z "$STORAGE_PG_WAL_DIR" ] && STORAGE_PG_WAL_DIR="${STORAGE_PG_DATA_DIR}/pg_wal"
      ;;
    *)
      [ -z "$STORAGE_PG_WAL_DIR" ] && STORAGE_PG_WAL_DIR="/pgwal"
      ;;
  esac
}

storage_data_mount_point() {
  dirname "$STORAGE_PG_DATA_DIR"
}

storage_wal_separate() {
  case "$STORAGE_LAYOUT_MODE" in
    4all) return 1 ;;
    *) return 0 ;;
  esac
}

storage_raid_level_for_role() {
  local role="$1"
  case "$STORAGE_LAYOUT_MODE" in
    8wal-raid10)
      [ "$role" = "wal" ] && echo 10 || echo 10
      ;;
    *)
      [ "$role" = "wal" ] && echo 1 || echo 10
      ;;
  esac
}
