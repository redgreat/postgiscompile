#!/bin/bash
set -u
if [ -n "${BASH_VERSION:-}" ]; then
  set -o pipefail 2>/dev/null || true
fi
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

INSTALLER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOWNLOAD_DIR="${INSTALLER_DIR}/packages"
OUT_DIR="${INSTALLER_DIR}/docs"
TS="$(date +'%Y%m%d_%H%M%S')"
OUT_FILE="${OUT_DIR}/os_preinstall_report_${TS}.md"
mkdir -p "$OUT_DIR" 2>/dev/null || true
if ! touch "$OUT_FILE" 2>/dev/null; then
  OUT_DIR="/tmp"
  OUT_FILE="${OUT_DIR}/os_preinstall_report_${TS}.md"
  mkdir -p "$OUT_DIR" 2>/dev/null || true
  touch "$OUT_FILE" 2>/dev/null || true
fi

# 检测操作系统
detect_os() {
    echo_info "正在检测操作系统类型和版本..."

    if [ -f /etc/os-release ]; then
        OS_TYPE=$(grep -oP '^NAME="\K[^"]+' /etc/os-release)
        OS_VERSION=$(grep -oP '^VERSION_ID="\K[^"]+' /etc/os-release)
    else
        echo_error "无法识别操作系统类型"
        exit 1
    fi

    MAJOR_VERSION=$(echo "$OS_VERSION" | awk -F'.' '{print $1}')
    if [ -z "$MAJOR_VERSION" ]; then
        echo_error "无法解析系统主版本号: $OS_VERSION"
        exit 1
    fi

    if [ "$MAJOR_VERSION" = "9" ]; then
        echo_success "操作系统检测完成: $OS_TYPE $OS_VERSION (主版本 9)"
        if [ -d "${DOWNLOAD_DIR}/rhel9" ]; then
            OS_SHORT="rhel9"
        elif [ -d "${DOWNLOAD_DIR}/rhel8" ]; then
            echo_warning "未找到 rhel9 包目录,回退使用 rhel8 包目录"
            OS_SHORT="rhel8"
        else
            echo_warning "未找到离线包目录,将跳过离线包安装"
            OS_SHORT=""
        fi
    elif [ "$MAJOR_VERSION" = "8" ]; then
        echo_success "操作系统检测完成: $OS_TYPE $OS_VERSION (主版本 8)"
        if [ -d "${DOWNLOAD_DIR}/rhel8" ]; then
            OS_SHORT="rhel8"
        elif [ -d "${DOWNLOAD_DIR}/rhel9" ]; then
            echo_warning "未找到 rhel8 包目录,回退使用 rhel9 包目录"
            OS_SHORT="rhel9"
        else
            echo_warning "未找到离线包目录,将跳过离线包安装"
            OS_SHORT=""
        fi
    else
        echo_warning "当前系统主版本: $MAJOR_VERSION,脚本主要适配 8/9,尝试继续"
        if [ -d "${DOWNLOAD_DIR}/rhel9" ]; then
            OS_SHORT="rhel9"
        elif [ -d "${DOWNLOAD_DIR}/rhel8" ]; then
            OS_SHORT="rhel8"
        else
            echo_warning "未找到离线包目录,将跳过离线包安装"
            OS_SHORT=""
        fi
    fi
}

# 导入 GPG 密钥
import_gpg_key() {
    local key_file="${DOWNLOAD_DIR}/${OS_SHORT}/RPM-GPG-KEY"
    if [ -f "$key_file" ]; then
        echo_info "导入 ${OS_SHORT} GPG 密钥..."
        rpm --import "$key_file" || {
            echo_warning "GPG 密钥导入失败,继续安装但可能提示 NOKEY"
            return 0
        }
        echo_success "GPG 密钥导入完成"
    else
        echo_warning "未找到 GPG 密钥文件,路径: $key_file,继续安装"
    fi
}

# 配置DNF本地仓库并生成元数据
setup_local_dnf_repo() {
    LOCAL_REPO_DIR="${DOWNLOAD_DIR}/${OS_SHORT}"
    LOCAL_REPO_ID="local-offline"
    LOCAL_REPO_FILE="/etc/yum.repos.d/${LOCAL_REPO_ID}.repo"

    if [ ! -d "${LOCAL_REPO_DIR}" ]; then
        echo_warning "未找到本地包目录:${LOCAL_REPO_DIR}"
        return 1
    fi

    if ! command -v createrepo_c >/dev/null 2>&1; then
        if compgen -G "${LOCAL_REPO_DIR}/createrepo_c-*.rpm" > /dev/null; then
            echo_info "正在使用本地RPM安装 createrepo_c..."
            dnf -y --disablerepo='*' --setopt=install_weak_deps=False --nogpgcheck --nobest --skip-broken install \
                "${LOCAL_REPO_DIR}/createrepo_c-"*.rpm \
                || echo_warning "createrepo_c 本地安装未完成或部分依赖缺失,继续"
        fi
    fi

    if command -v createrepo_c >/dev/null 2>&1; then
        createrepo_c "${LOCAL_REPO_DIR}" >/dev/null 2>&1 || true
    elif command -v createrepo >/dev/null 2>&1; then
        createrepo "${LOCAL_REPO_DIR}" >/dev/null 2>&1 || true
    fi

    if [ -f "${LOCAL_REPO_DIR}/repodata/repomd.xml" ]; then
        cat > "${LOCAL_REPO_FILE}" <<EOF
[${LOCAL_REPO_ID}]
name=Local Offline Repo
baseurl=file://${LOCAL_REPO_DIR}
enabled=1
gpgcheck=0
EOF
        dnf clean all >/dev/null 2>&1 || true
        dnf makecache --disablerepo='*' --enablerepo="${LOCAL_REPO_ID}" >/dev/null 2>&1 || true
    else
        rm -f "${LOCAL_REPO_FILE}" 2>/dev/null || true
        echo_warning "未检测到本地仓库元数据,将改用本地RPM文件安装"
    fi
}

# 使用DNF从本地仓库或本地RPM文件安装一组软件包
dnf_install_local() {
    local mode="${1:-optional}"; shift
    local pkgs=("$@")
    local repo_id="local-offline"
    local repo_dir="${DOWNLOAD_DIR}/${OS_SHORT}"

    if [ ${#pkgs[@]} -eq 0 ]; then
        return 0
    fi

    local have_repo=0
    if [ -f "/etc/yum.repos.d/${repo_id}.repo" ] && [ -f "${repo_dir}/repodata/repomd.xml" ]; then
        have_repo=1
    fi

    if [ ${have_repo} -eq 1 ]; then
        if dnf -y --disablerepo='*' --enablerepo="${repo_id}" --setopt=install_weak_deps=False --nogpgcheck --nobest install "${pkgs[@]}"; then
            echo_success "DNF 安装完成:${pkgs[*]}"
            return 0
        fi
        echo_warning "DNF仓库安装失败,尝试以本地RPM文件直接安装..."
    fi

    local files=()
    for p in "${pkgs[@]}"; do
        local matches=("${repo_dir}/"${p}*.rpm)
        if [ ${#matches[@]} -eq 0 ]; then
            if [ "${mode}" = "required" ]; then
                echo_error "缺少必需包或RPM:${p}"
                exit 1
            else
                echo_warning "未找到匹配RPM:${p},跳过"
            fi
            continue
        fi
        files+=("${matches[@]}")
    done

    if [ ${#files[@]} -eq 0 ]; then
        return 0
    fi

    if dnf -y --disablerepo='*' --setopt=install_weak_deps=False --nogpgcheck --nobest install "${files[@]}"; then
        echo_success "DNF 本地RPM安装完成:${pkgs[*]}"
    else
        echo_warning "DNF 安装失败:${pkgs[*]}"
        if [ "${mode}" = "required" ]; then
            exit 1
        fi
    fi
}

# 安装系统检测工具
install_report_tools() {
    if [ -z "${OS_SHORT:-}" ]; then
        echo_warning "未检测到离线包目录,跳过工具安装"
        return 0
    fi

    echo_info "正在安装系统检测工具..."

    import_gpg_key
    setup_local_dnf_repo

    # 安装系统检测工具
    dnf_install_local optional \
        coreutils procps-ng util-linux systemd systemd-udev pciutils dmidecode smartmontools \
        mdadm device-mapper-multipath lvm2 device-mapper fio virt-what bc fio-engine-libaio

    echo_success "系统检测工具安装完成"
}

# 询问 PostgreSQL 数据目录
if [ -t 0 ]; then
  echo "请输入 PostgreSQL 数据目录路径 (默认: /opt/postgresql/data): "
  read -r PG_DATA_DIR
  PG_DATA_DIR="${PG_DATA_DIR:-/opt/postgresql/data}"
else
  PG_DATA_DIR="${PG_DATA_DIR:-/opt/postgresql/data}"
fi

# 确定数据目录所在的挂载点
DATA_DIR_EXISTS=true
ACTUAL_TEST_DIR="$PG_DATA_DIR"
SKIP_IO_TEST=false

if [ -d "$PG_DATA_DIR" ]; then
  TARGET_MOUNT=$(df "$PG_DATA_DIR" | tail -1 | awk '{print $6}')
else
  # 如果目录不存在,找到其父目录的挂载点
  DATA_DIR_EXISTS=false
  echo_warning "数据目录不存在: $PG_DATA_DIR"
  
  PARENT_DIR=$(dirname "$PG_DATA_DIR")
  while [ ! -d "$PARENT_DIR" ] && [ "$PARENT_DIR" != "/" ]; do
    PARENT_DIR=$(dirname "$PARENT_DIR")
  done
  
  # 检查父目录是否存在且可写
  if [ -d "$PARENT_DIR" ]; then
    ACTUAL_TEST_DIR="$PARENT_DIR"
    TARGET_MOUNT=$(df "$PARENT_DIR" 2>/dev/null | tail -1 | awk '{print $6}' || echo "/")
    echo_info "找到存在的父目录: $PARENT_DIR"
    echo_info "将测试父目录的挂载点: $TARGET_MOUNT"
    
    # 检查父目录是否可写
    if [ ! -w "$PARENT_DIR" ]; then
      echo_warning "父目录不可写,将跳过 IO 测试"
      SKIP_IO_TEST=true
    fi
  else
    echo_error "无法找到有效的父目录,将跳过 IO 测试"
    SKIP_IO_TEST=true
    TARGET_MOUNT="/"
    ACTUAL_TEST_DIR="/"
  fi
fi

echo "数据目录: $PG_DATA_DIR"
if [ "$DATA_DIR_EXISTS" = "false" ]; then
  echo_warning "⚠️  数据目录不存在"
  echo "实际测试目录: $ACTUAL_TEST_DIR"
  if [ "$SKIP_IO_TEST" = "true" ]; then
    echo_warning "⚠️  无有效测试目录,将跳过 IO 测试"
  fi
fi
echo "挂载点: $TARGET_MOUNT"
echo "报告文件: $OUT_FILE"
echo ""

append() { printf "%s\n" "$1" >> "$OUT_FILE"; }
section() { append ""; append "## $1"; append ""; }
block() {
  append "\`\`\`"
  "$@" >> "$OUT_FILE" 2>&1 || true
  append "\`\`\`"
}
line() { append "$1"; }

collect_os() {
  section "系统信息"
  
  if [ -f /etc/os-release ]; then
    OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    append "- 操作系统: ${OS_NAME}"
  fi
  
  KERNEL=$(uname -r)
  append "- 内核版本: ${KERNEL}"
  
  UPTIME_INFO=$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
  append "- 运行时间: ${UPTIME_INFO}"
  
  # 虚拟化信息
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
    case "$VIRT_TYPE" in
      microsoft) append "- 虚拟化: Hyper-V" ;;
      kvm) append "- 虚拟化: KVM" ;;
      vmware) append "- 虚拟化: VMware" ;;
      xen) append "- 虚拟化: Xen" ;;
      none) append "- 虚拟化: 物理机" ;;
      *) append "- 虚拟化: ${VIRT_TYPE}" ;;
    esac
  fi
}

collect_cpu() {
  section "CPU 信息"
  
  CPU_MODEL=$(lscpu | grep '^Model name:' | sed 's/Model name:[[:space:]]*//')
  CPU_CORES=$(lscpu | grep '^CPU(s):' | head -1 | awk '{print $2}')
  CPU_ARCH=$(lscpu | grep '^Architecture:' | awk '{print $2}')
  CPU_MHZ=$(lscpu | grep '^CPU MHz:' | awk '{print $3}' || echo "")
  CPU_MAX_MHZ=$(lscpu | grep '^CPU max MHz:' | awk '{print $4}' || echo "")
  
  append "- 型号: ${CPU_MODEL}"
  append "- 架构: ${CPU_ARCH}"
  append "- 核心数: ${CPU_CORES}"
  
  # 主频信息
  if [ -n "$CPU_MHZ" ]; then
    CPU_GHZ=$(echo "scale=2; $CPU_MHZ / 1000" | bc 2>/dev/null || echo "$CPU_MHZ MHz")
    if [ -n "$CPU_MAX_MHZ" ]; then
      CPU_MAX_GHZ=$(echo "scale=2; $CPU_MAX_MHZ / 1000" | bc 2>/dev/null || echo "$CPU_MAX_MHZ MHz")
      append "- 主频: ${CPU_GHZ} GHz (最高 ${CPU_MAX_GHZ} GHz)"
    else
      append "- 主频: ${CPU_GHZ} GHz"
    fi
  fi
  
  if echo "$CPU_MODEL" | grep -q 'Intel'; then
    GEN=$(echo "$CPU_MODEL" | grep -oP '\d+(?:st|nd|rd|th) Gen' || echo "")
    if [ -n "$GEN" ]; then
      append "- Intel 代数: ${GEN}"
    fi
  fi
}

collect_memory() {
  section "内存信息"
  
  MEM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
  MEM_AVAIL=$(free -h | awk '/^Mem:/ {print $7}')
  SWAP_TOTAL=$(free -h | awk '/^Swap:/ {print $2}')
  
  append "- 总内存: ${MEM_TOTAL}"
  append "- 可用内存: ${MEM_AVAIL}"
  append "- 交换分区: ${SWAP_TOTAL}"
  
  # 尝试获取内存频率(需要 dmidecode)
  if command -v dmidecode >/dev/null 2>&1; then
    MEM_SPEED=$(dmidecode -t memory 2>/dev/null | grep -i "Speed:" | grep -v "Unknown" | grep -oP '\d+ MT/s' | head -1 || echo "")
    MEM_TYPE=$(dmidecode -t memory 2>/dev/null | grep -i "Type:" | grep -v "Type Detail" | grep -v "Error Correction" | awk '{print $2}' | grep -E "DDR[0-9]" | head -1 || echo "")
    if [ -n "$MEM_SPEED" ] || [ -n "$MEM_TYPE" ]; then
      MEM_INFO=""
      [ -n "$MEM_TYPE" ] && MEM_INFO="$MEM_TYPE"
      [ -n "$MEM_SPEED" ] && MEM_INFO="$MEM_INFO $MEM_SPEED"
      append "- 内存类型: ${MEM_INFO}"
    fi
  fi
}

collect_disk_simple() {
  section "磁盘信息"
  
  append "### 磁盘列表"
  append ""
  lsblk -dn -o NAME,SIZE,TYPE,MODEL | while read name size type model; do
    if [ "$type" = "disk" ]; then
      append "- /dev/${name}: ${size} - ${model}"
    fi
  done
  
  append ""
  append "### 分区布局"
  append ""
  block lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
}

collect_target_mount() {
  section "数据目录挂载点信息"
  
  append "**目标路径:** $PG_DATA_DIR"
  
  # 检查目录是否存在
  if [ "$DATA_DIR_EXISTS" = "false" ]; then
    append "**状态:** ⚠️ 目录不存在"
    append "**实际测试目录:** $ACTUAL_TEST_DIR"
    if [ "$SKIP_IO_TEST" = "true" ]; then
      append "**IO测试:** ⚠️ 已跳过 (父目录不存在或不可写)"
    fi
  else
    append "**状态:** ✅ 目录存在"
  fi
  
  append "**挂载点:** $TARGET_MOUNT"
  append ""
  
  # 获取挂载点详细信息
  MOUNT_INFO=$(findmnt -rn -o SOURCE,FSTYPE,SIZE,AVAIL,USE% -T "$TARGET_MOUNT" 2>/dev/null || echo "- - - - -")
  read SOURCE FSTYPE SIZE AVAIL USE <<< "$MOUNT_INFO"
  
  append "- 设备: ${SOURCE}"
  append "- 文件系统: ${FSTYPE}"
  append "- 总容量: ${SIZE}"
  append "- 可用空间: ${AVAIL}"
  append "- 使用率: ${USE}"
  
  # 找到底层块设备
  BLOCK_DEV=$(lsblk -no PKNAME "$SOURCE" 2>/dev/null | head -1)
  if [ -z "$BLOCK_DEV" ]; then
    BLOCK_DEV=$(echo "$SOURCE" | sed 's|/dev/mapper/.*|sda|;s|/dev/||;s|[0-9]*$||')
  fi
  
  if [ -n "$BLOCK_DEV" ]; then
    append ""
    append "**底层块设备:** /dev/${BLOCK_DEV}"
    
    # 获取块设备信息
    DISK_INFO=$(lsblk -dn -o SIZE,MODEL "/dev/${BLOCK_DEV}" 2>/dev/null || echo "- -")
    read DISK_SIZE DISK_MODEL <<< "$DISK_INFO"
    append "- 磁盘大小: ${DISK_SIZE}"
    append "- 磁盘型号: ${DISK_MODEL}"
  fi
}

run_io_tests() {
  section "磁盘 IO 性能测试"
  
  # 检查是否需要跳过 IO 测试
  if [ "$SKIP_IO_TEST" = "true" ]; then
    append "**测试状态:** ⚠️ 已跳过"
    append ""
    append "**原因:** 数据目录及其父目录不存在或不可写"
    append ""
    append "**建议:**"
    append "- 创建数据目录后重新运行此脚本"
    append "- 或者测试其他已存在的目录"
    return
  fi
  
  append "**测试目标:** $ACTUAL_TEST_DIR"
  if [ "$DATA_DIR_EXISTS" = "false" ]; then
    append "**说明:** 数据目录不存在,测试父目录 $ACTUAL_TEST_DIR"
  fi
  append ""
  
  SIZE_MB="${PG_IO_TEST_SIZE_MB:-256}"
  RUNTIME_SEC="${PG_IO_TEST_RUNTIME_SEC:-20}"
  
  # 检查是否可写
  if [ ! -w "$ACTUAL_TEST_DIR" ]; then
    append "⚠️ 测试目录不可写,跳过 IO 测试"
    return
  fi
  
  testfile="${ACTUAL_TEST_DIR}/.pg_io_test_${TS}.bin"
  
  if command -v fio >/dev/null 2>&1; then
    echo "正在进行 IO 性能测试,请稍候..."
    echo "测试文件: $testfile"
    echo "测试目录: $ACTUAL_TEST_DIR"
    
    # 测试 fio 是否可以正常工作
    echo "检查 fio 命令..."
    if ! fio --version >/dev/null 2>&1; then
      echo_error "fio 命令无法正常运行"
      append "**错误:** fio 命令无法正常运行"
      return
    fi
    
    # 顺序写测试
    SEQ_WRITE_OUT="/tmp/fio_seq_write_${TS}.log"
    echo "  - 顺序写测试..."
    set +e
    fio --name=seq_write --filename="${testfile}" --size="${SIZE_MB}M" --rw=write --bs=1M --direct=1 --iodepth=32 --ioengine=libaio --runtime="${RUNTIME_SEC}" --group_reporting > "$SEQ_WRITE_OUT" 2>&1
    FIO_EXIT=$?
    set -e
    
    if [ $FIO_EXIT -eq 0 ] && [ -f "$SEQ_WRITE_OUT" ]; then
      echo "    ✓ 测试成功"
      SEQ_WRITE_BW=$(grep -i "write:.*BW=" "$SEQ_WRITE_OUT" | grep -oP 'BW=\K[0-9.]+[MGK]iB/s' | head -1 || echo "N/A")
    else
      echo "    ✗ 测试失败 (退出码: $FIO_EXIT)"
      if [ -f "$SEQ_WRITE_OUT" ]; then
        echo "    错误信息:"
        head -20 "$SEQ_WRITE_OUT" | sed 's/^/      /'
      else
        echo "    未生成日志文件"
      fi
      SEQ_WRITE_BW="N/A"
    fi
    echo "    提取结果: $SEQ_WRITE_BW"
    
    # 顺序读测试
    SEQ_READ_OUT="/tmp/fio_seq_read_${TS}.log"
    echo "  - 顺序读测试..."
    if fio --name=seq_read --filename="${testfile}" --size="${SIZE_MB}M" --rw=read --bs=1M --direct=1 --iodepth=32 --ioengine=libaio --runtime="${RUNTIME_SEC}" --group_reporting > "$SEQ_READ_OUT" 2>&1; then
      echo "    ✓ 测试成功"
      SEQ_READ_BW=$(grep -i "read:.*BW=" "$SEQ_READ_OUT" | grep -oP 'BW=\K[0-9.]+[MGK]iB/s' | head -1 || echo "N/A")
    else
      echo "    ✗ 测试失败,查看错误: cat $SEQ_READ_OUT"
      SEQ_READ_BW="N/A"
    fi
    echo "    提取结果: $SEQ_READ_BW"
    
    # 随机读测试
    RAND_READ_OUT="/tmp/fio_rand_read_${TS}.log"
    echo "  - 随机读测试..."
    if fio --name=rand_read --filename="${testfile}" --size="${SIZE_MB}M" --rw=randread --bs=4k --direct=1 --iodepth=64 --numjobs=4 --ioengine=libaio --runtime="${RUNTIME_SEC}" --group_reporting > "$RAND_READ_OUT" 2>&1; then
      echo "    ✓ 测试成功"
      RAND_READ_IOPS=$(grep -i "read:.*IOPS=" "$RAND_READ_OUT" | grep -oP 'IOPS=\K[0-9.]+[kM]?' | head -1 || echo "N/A")
    else
      echo "    ✗ 测试失败,查看错误: cat $RAND_READ_OUT"
      RAND_READ_IOPS="N/A"
    fi
    echo "    提取结果: $RAND_READ_IOPS"
    
    # 随机写测试
    RAND_WRITE_OUT="/tmp/fio_rand_write_${TS}.log"
    echo "  - 随机写测试..."
    if fio --name=rand_write --filename="${testfile}" --size="${SIZE_MB}M" --rw=randwrite --bs=4k --direct=1 --iodepth=64 --numjobs=4 --ioengine=libaio --runtime="${RUNTIME_SEC}" --group_reporting > "$RAND_WRITE_OUT" 2>&1; then
      echo "    ✓ 测试成功"
      RAND_WRITE_IOPS=$(grep -i "write:.*IOPS=" "$RAND_WRITE_OUT" | grep -oP 'IOPS=\K[0-9.]+[kM]?' | head -1 || echo "N/A")
    else
      echo "    ✗ 测试失败,查看错误: cat $RAND_WRITE_OUT"
      RAND_WRITE_IOPS="N/A"
    fi
    echo "    提取结果: $RAND_WRITE_IOPS"
    
    echo "  ✓ 测试完成"
    echo ""
    
    # 显示结果
    append "### 测试结果"
    append ""
    append "| 测试项目 | 性能指标 |"
    append "|---------|---------|"
    append "| 顺序写带宽 | ${SEQ_WRITE_BW} |"
    append "| 顺序读带宽 | ${SEQ_READ_BW} |"
    append "| 随机读 IOPS | ${RAND_READ_IOPS} |"
    append "| 随机写 IOPS | ${RAND_WRITE_IOPS} |"
    append ""
    
    # 调试信息
    echo "调试信息:"
    echo "  顺序写: $SEQ_WRITE_BW"
    echo "  顺序读: $SEQ_READ_BW"
    echo "  随机读: $RAND_READ_IOPS"
    echo "  随机写: $RAND_WRITE_IOPS"
    echo ""
    
    # 性能评估
    rand_r_num=$(echo "$RAND_READ_IOPS" | sed 's/k/*1000/;s/M/*1000000/;s/[^0-9.*]//g' | bc 2>/dev/null || echo "0")
    rand_w_num=$(echo "$RAND_WRITE_IOPS" | sed 's/k/*1000/;s/M/*1000000/;s/[^0-9.*]//g' | bc 2>/dev/null || echo "0")
    
    append "### 性能评估"
    append ""
    
    if [ $(echo "$rand_r_num >= 100000" | bc 2>/dev/null || echo "0") -eq 1 ]; then
      PERF_LEVEL="企业级 NVMe SSD"
      RATING="⭐⭐⭐⭐⭐"
      RECOMMENDATION="✅ 强烈推荐用于 PostgreSQL 生产环境"
    elif [ $(echo "$rand_r_num >= 50000" | bc 2>/dev/null || echo "0") -eq 1 ]; then
      PERF_LEVEL="高性能 SSD"
      RATING="⭐⭐⭐⭐"
      RECOMMENDATION="✅ 推荐用于 PostgreSQL 生产环境"
    elif [ $(echo "$rand_r_num >= 10000" | bc 2>/dev/null || echo "0") -eq 1 ]; then
      PERF_LEVEL="普通 SSD"
      RATING="⭐⭐⭐"
      RECOMMENDATION="⚠️ 可用于中小型 PostgreSQL 数据库"
    elif [ $(echo "$rand_r_num >= 1000" | bc 2>/dev/null || echo "0") -eq 1 ]; then
      PERF_LEVEL="SATA SSD 或高速 HDD"
      RATING="⭐⭐"
      RECOMMENDATION="⚠️ 仅适合开发测试环境"
    else
      PERF_LEVEL="传统 HDD"
      RATING="⭐"
      RECOMMENDATION="❌ 不推荐用于 PostgreSQL"
    fi
    
    append "- **磁盘类型:** ${PERF_LEVEL}"
    append "- **性能评分:** ${RATING}"
    append "- **建议:** ${RECOMMENDATION}"
    
    # 清理临时文件
    rm -f "$SEQ_WRITE_OUT" "$SEQ_READ_OUT" "$RAND_READ_OUT" "$RAND_WRITE_OUT" "${testfile}" 2>/dev/null || true
  else
    append "⚠️ 未安装 fio 工具,无法进行详细的 IO 测试"
    append ""
    append "安装方法: \`dnf install fio\` 或 \`apt install fio\`"
  fi
}

main() {
  # 检测操作系统并安装必要工具
  detect_os
  install_report_tools
  
  echo ""
  echo_info "开始生成系统检查报告..."
  echo ""
  
  append "# PostgreSQL 安装前系统检查报告"
  line ""
  line "生成时间: $(date +'%Y年%m月%d日 %H:%M:%S')"
  line "数据目录: $PG_DATA_DIR"
  line "挂载点: $TARGET_MOUNT"
  line ""
  
  collect_os
  collect_cpu
  collect_memory
  collect_disk_simple
  collect_target_mount
  run_io_tests
  
  append ""
  append "---"
  append "报告生成完成"
  
  echo ""
  echo "✅ 报告已生成: $OUT_FILE"
}

main
