#!/bin/bash

# Rocky Linux 9 离线环境检查脚本
# 用途：在运行安装脚本前，检查离线环境是否准备就绪

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOWNLOAD_DIR="${PROJECT_ROOT}/packages/rockylinux9"

# 计数器
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Rocky Linux 9 离线环境检查${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查函数
check_command() {
    local cmd=$1
    local desc=$2
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if command -v "$cmd" &> /dev/null; then
        echo -e "${GREEN}[✓]${NC} $desc: $(command -v $cmd)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}[✗]${NC} $desc: 未安装"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

check_file() {
    local file=$1
    local desc=$2
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [ -f "$file" ]; then
        local size=$(du -h "$file" | cut -f1)
        echo -e "${GREEN}[✓]${NC} $desc: $size"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}[✗]${NC} $desc: 文件不存在"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

check_header() {
    local header=$1
    local desc=$2
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [ -f "$header" ]; then
        echo -e "${GREEN}[✓]${NC} $desc"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${YELLOW}[!]${NC} $desc: 未安装（可选）"
        WARNING_CHECKS=$((WARNING_CHECKS + 1))
        return 1
    fi
}

# 1. 检查基础编译工具
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}1. 基础编译工具检查${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

check_command gcc "GCC 编译器"
check_command g++ "G++ 编译器"
check_command make "Make 构建工具"
check_command tar "Tar 解压工具"
check_command bzip2 "Bzip2 压缩工具"
check_command xz "XZ 压缩工具"

echo ""

# 2. 检查系统开发库
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}2. 系统开发库检查${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

check_header "/usr/include/openssl/ssl.h" "OpenSSL 开发库"
check_header "/usr/include/readline/readline.h" "Readline 开发库"
check_header "/usr/include/zlib.h" "Zlib 开发库"

echo ""

# 3. 检查源码包
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}3. 源码包检查${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

check_file "${DOWNLOAD_DIR}/postgresql-18.1.tar.bz2" "PostgreSQL 18.1"
check_file "${DOWNLOAD_DIR}/postgis-3.6.0.tar.gz" "PostGIS 3.6.0"
check_file "${DOWNLOAD_DIR}/geos-3.14.0.tar.bz2" "GEOS 3.14.0"
check_file "${DOWNLOAD_DIR}/proj-9.7.0.tar.gz" "PROJ 9.7.0"
check_file "${DOWNLOAD_DIR}/sqlite-autoconf-3460000.tar.gz" "SQLite 3.46.0"
check_file "${DOWNLOAD_DIR}/cmake-3.31.3.tar.gz" "CMake 3.31.3"
check_file "${DOWNLOAD_DIR}/protobuf-c-1.5.2.tar.gz" "protobuf-c 1.5.2"

# JSON-C 可能有两种文件名
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ -f "${DOWNLOAD_DIR}/json-c-0.18-20240915.tar.gz" ] || [ -f "${DOWNLOAD_DIR}/json-c-json-c-0.18-20240915.tar.gz" ]; then
    echo -e "${GREEN}[✓]${NC} JSON-C 0.18"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo -e "${RED}[✗]${NC} JSON-C 0.18: 文件不存在"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

echo ""

# 4. 检查 RPM 包
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}4. RPM 包检查${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查基础工具 RPM
RPM_BASE_DIR="${DOWNLOAD_DIR}/rpm_base"
if [ ! -d "$RPM_BASE_DIR" ]; then
    # 如果没有专门的 base 目录，尝试在主目录或 rpm 目录查找
    RPM_BASE_DIR="${DOWNLOAD_DIR}"
fi

echo "基础工具 (如果系统未安装则需要):"
check_file "${RPM_BASE_DIR}/gcc-11.5.0-5.el9_5.x86_64.rpm" "GCC" || \
check_file "${DOWNLOAD_DIR}/rpm/gcc-11.5.0-5.el9_5.x86_64.rpm" "GCC (备选路径)"

check_file "${RPM_BASE_DIR}/gcc-c++-11.5.0-5.el9_5.x86_64.rpm" "G++" || \
check_file "${DOWNLOAD_DIR}/rpm/gcc-c++-11.5.0-5.el9_5.x86_64.rpm" "G++ (备选路径)"

check_file "${RPM_BASE_DIR}/make-4.3-8.el9.x86_64.rpm" "Make" || \
check_file "${DOWNLOAD_DIR}/rpm/make-4.3-8.el9.x86_64.rpm" "Make (备选路径)"

check_file "${RPM_BASE_DIR}/tar-1.34-7.el9.x86_64.rpm" "Tar" || \
check_file "${DOWNLOAD_DIR}/rpm/tar-1.34-7.el9.x86_64.rpm" "Tar (备选路径)"

check_file "${RPM_BASE_DIR}/bzip2-1.0.8-10.el9_5.x86_64.rpm" "Bzip2" || \
check_file "${DOWNLOAD_DIR}/rpm/bzip2-1.0.8-10.el9_5.x86_64.rpm" "Bzip2 (备选路径)"

check_file "${RPM_BASE_DIR}/xz-5.2.5-8.el9_0.x86_64.rpm" "XZ" || \
check_file "${DOWNLOAD_DIR}/rpm/xz-5.2.5-8.el9_0.x86_64.rpm" "XZ (备选路径)"

echo ""
echo "编译依赖工具:"

RPM_DIR="${DOWNLOAD_DIR}/rpm"
if [ ! -d "$RPM_DIR" ]; then
    RPM_DIR="${DOWNLOAD_DIR}"
fi

check_file "${RPM_DIR}/m4-1.4.19-1.el9.x86_64.rpm" "M4 宏处理器"
check_file "${RPM_DIR}/gettext-0.22.5-2.el9.x86_64.rpm" "Gettext 工具"
check_file "${RPM_DIR}/autoconf-2.71-3.el9.noarch.rpm" "Autoconf 工具"
check_file "${RPM_DIR}/automake-1.16.5-11.el9.noarch.rpm" "Automake 工具"
check_file "${RPM_DIR}/bison-3.7.4-5.el9.x86_64.rpm" "Bison 工具"

echo ""

# 5. 检查安装脚本
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}5. 安装脚本检查${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

check_file "${PROJECT_ROOT}/bin/rockylinux9_install.sh" "安装脚本"

echo ""

# 6. 检查权限
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}6. 权限检查${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ "$(id -u)" -eq 0 ]; then
    echo -e "${GREEN}[✓]${NC} Root 权限: 是"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo -e "${YELLOW}[!]${NC} Root 权限: 否（安装时需要 root 权限）"
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
fi

echo ""

# 7. 检查磁盘空间
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}7. 磁盘空间检查${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
AVAILABLE_SPACE=$(df /opt | tail -1 | awk '{print $4}')
REQUIRED_SPACE=$((15 * 1024 * 1024))  # 15GB in KB

if [ "$AVAILABLE_SPACE" -gt "$REQUIRED_SPACE" ]; then
    echo -e "${GREEN}[✓]${NC} /opt 可用空间: $(df -h /opt | tail -1 | awk '{print $4}') (需要至少 15GB)"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    echo -e "${RED}[✗]${NC} /opt 可用空间不足: $(df -h /opt | tail -1 | awk '{print $4}') (需要至少 15GB)"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

echo ""

# 总结
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}检查总结${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo "总检查项: $TOTAL_CHECKS"
echo -e "${GREEN}通过: $PASSED_CHECKS${NC}"
echo -e "${YELLOW}警告: $WARNING_CHECKS${NC}"
echo -e "${RED}失败: $FAILED_CHECKS${NC}"
echo ""

# 给出建议
if [ $FAILED_CHECKS -eq 0 ]; then
    if [ $WARNING_CHECKS -eq 0 ]; then
        echo -e "${GREEN}✓ 所有检查通过！环境已准备就绪。${NC}"
        echo ""
        echo "可以运行安装脚本："
        echo "  cd ${PROJECT_ROOT}"
        echo "  bash bin/rockylinux9_install.sh"
    else
        echo -e "${YELLOW}⚠ 有警告项，但可以继续安装。${NC}"
        echo ""
        echo "警告说明："
        if [ "$(id -u)" -ne 0 ]; then
            echo "  - 需要 root 权限运行安装脚本"
        fi
        if [ ! -f "/usr/include/openssl/ssl.h" ] || [ ! -f "/usr/include/readline/readline.h" ] || [ ! -f "/usr/include/zlib.h" ]; then
            echo "  - 缺少可选的系统开发库，建议安装以获得完整功能"
            echo "    安装方法: dnf install -y openssl-devel readline-devel zlib-devel"
        fi
    fi
else
    echo -e "${RED}✗ 检查失败！请先解决以下问题：${NC}"
    echo ""
    
    # 检查缺少的编译工具
    if ! command -v gcc &> /dev/null || ! command -v g++ &> /dev/null || ! command -v make &> /dev/null; then
        echo "1. 缺少基础编译工具"
        echo "   安装方法（有网络）:"
        echo "     dnf install -y gcc gcc-c++ make tar bzip2 xz"
        echo ""
        echo "   安装方法（离线）:"
        echo "     使用 Rocky Linux 9 ISO 或从镜像站下载 RPM 包"
        echo "     参考文档: docs/rockylinux9_offline_preparation.md"
        echo ""
    fi
    
    # 检查缺少的源码包
    missing_sources=()
    [ ! -f "${DOWNLOAD_DIR}/postgresql-18.1.tar.bz2" ] && missing_sources+=("postgresql-18.1.tar.bz2")
    [ ! -f "${DOWNLOAD_DIR}/postgis-3.6.0.tar.gz" ] && missing_sources+=("postgis-3.6.0.tar.gz")
    [ ! -f "${DOWNLOAD_DIR}/geos-3.14.0.tar.bz2" ] && missing_sources+=("geos-3.14.0.tar.bz2")
    [ ! -f "${DOWNLOAD_DIR}/proj-9.7.0.tar.gz" ] && missing_sources+=("proj-9.7.0.tar.gz")
    
    if [ ${#missing_sources[@]} -gt 0 ]; then
        echo "2. 缺少源码包"
        echo "   缺少的文件:"
        for src in "${missing_sources[@]}"; do
            echo "     - $src"
        done
        echo ""
        echo "   下载方法:"
        echo "     参考文档: packages/rockylinux9/packages_list.txt"
        echo ""
    fi
    
    # 检查磁盘空间
    if [ "$AVAILABLE_SPACE" -le "$REQUIRED_SPACE" ]; then
        echo "3. 磁盘空间不足"
        echo "   当前可用: $(df -h /opt | tail -1 | awk '{print $4}')"
        echo "   需要至少: 15GB"
        echo ""
    fi
fi

echo ""
echo "详细文档："
echo "  - 离线环境准备: ${PROJECT_ROOT}/docs/rockylinux9_offline_preparation.md"
echo "  - 包下载位置: ${PROJECT_ROOT}/docs/rockylinux9_rpm_download_locations.md"
echo "  - 快速参考: ${PROJECT_ROOT}/docs/rockylinux9_rpm_quick_reference.md"
echo ""

# 退出状态
if [ $FAILED_CHECKS -gt 0 ]; then
    exit 1
else
    exit 0
fi
