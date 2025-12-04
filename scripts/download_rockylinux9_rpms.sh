#!/bin/bash
# Rocky Linux 9 RPM 包下载脚本
# 用途：下载 PostgreSQL 18 + PostGIS 3.6.0 编译所需的系统工具包

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOWNLOAD_DIR="${PROJECT_ROOT}/packages/rockylinux9/rpm"
BASE_URL="https://dl.rockylinux.org/vault/rocky/9.6"

# 创建下载目录
mkdir -p "$DOWNLOAD_DIR"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Rocky Linux 9 RPM 包下载脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "下载目录: $DOWNLOAD_DIR"
echo "镜像站: $BASE_URL"
echo ""

# 切换到下载目录
cd "$DOWNLOAD_DIR"

# 定义要下载的包（格式：包名|仓库|首字母目录）
declare -a PACKAGES=(
    "m4-1.4.19-1.el9.x86_64.rpm|AppStream|m"
    "gettext-0.22.5-2.el9.x86_64.rpm|BaseOS|g"
    "autoconf-2.71-3.el9.noarch.rpm|AppStream|a"
    "automake-1.16.5-11.el9.noarch.rpm|AppStream|a"
    "bison-3.7.4-5.el9.x86_64.rpm|AppStream|b"
)

# 可选的开发包（可能需要从 CRB 仓库下载）
declare -a OPTIONAL_PACKAGES=(
    "libxml2-devel"
    "libxslt-devel"
)

# 下载函数
download_package() {
    local package_name=$1
    local repo=$2
    local letter=$3
    local url="${BASE_URL}/${repo}/x86_64/os/Packages/${letter}/${package_name}"
    
    if [ -f "$package_name" ]; then
        echo -e "${YELLOW}[跳过]${NC} $package_name (已存在)"
        return 0
    fi
    
    echo -e "${GREEN}[下载]${NC} $package_name"
    echo "  URL: $url"
    
    if wget -q --show-progress "$url"; then
        echo -e "${GREEN}[成功]${NC} $package_name"
        return 0
    else
        echo -e "${RED}[失败]${NC} $package_name"
        
        # 如果从 BaseOS 下载失败，尝试从 AppStream 下载
        if [ "$repo" = "BaseOS" ]; then
            echo -e "${YELLOW}[重试]${NC} 尝试从 AppStream 仓库下载..."
            local alt_url="${BASE_URL}/AppStream/x86_64/os/Packages/${letter}/${package_name}"
            if wget -q --show-progress "$alt_url"; then
                echo -e "${GREEN}[成功]${NC} $package_name (从 AppStream)"
                return 0
            fi
        fi
        
        return 1
    fi
}

# 下载主要包
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}1. 下载必需的 RPM 包${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

FAILED_PACKAGES=()

for package_info in "${PACKAGES[@]}"; do
    IFS='|' read -r package repo letter <<< "$package_info"
    if ! download_package "$package" "$repo" "$letter"; then
        FAILED_PACKAGES+=("$package")
    fi
    echo ""
done

# 显示可选包信息
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}2. 可选开发包${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "以下开发包为可选依赖，建议在有网络的 Rocky Linux 系统上使用以下命令下载："
echo ""
echo -e "${YELLOW}方法 1: 使用 dnf download${NC}"
echo "  dnf download libxml2-devel libxslt-devel"
echo ""
echo -e "${YELLOW}方法 2: 使用 repotrack (包含依赖)${NC}"
echo "  repotrack libxml2-devel libxslt-devel"
echo ""
echo "这些包通常位于以下位置："
for pkg in "${OPTIONAL_PACKAGES[@]}"; do
    echo "  - ${BASE_URL}/AppStream/x86_64/os/Packages/l/${pkg}-*.el9.x86_64.rpm"
    echo "  - ${BASE_URL}/CRB/x86_64/os/Packages/l/${pkg}-*.el9.x86_64.rpm"
done
echo ""

# 下载摘要
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}下载摘要${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

TOTAL_PACKAGES=${#PACKAGES[@]}
FAILED_COUNT=${#FAILED_PACKAGES[@]}
SUCCESS_COUNT=$((TOTAL_PACKAGES - FAILED_COUNT))

echo "总计: $TOTAL_PACKAGES 个包"
echo -e "${GREEN}成功: $SUCCESS_COUNT${NC}"

if [ $FAILED_COUNT -gt 0 ]; then
    echo -e "${RED}失败: $FAILED_COUNT${NC}"
    echo ""
    echo "失败的包："
    for pkg in "${FAILED_PACKAGES[@]}"; do
        echo -e "  ${RED}✗${NC} $pkg"
    done
    echo ""
    echo -e "${YELLOW}提示：${NC}"
    echo "1. 检查网络连接"
    echo "2. 包版本可能已更新，请访问以下地址查看最新版本："
    echo "   ${BASE_URL}/AppStream/x86_64/os/Packages/"
    echo "3. 可以手动下载失败的包"
else
    echo ""
    echo -e "${GREEN}✓ 所有包下载成功！${NC}"
fi

echo ""

# 列出已下载的文件
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}已下载的文件${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if ls *.rpm &> /dev/null; then
    ls -lh *.rpm | awk '{printf "  %-40s %10s\n", $9, $5}'
    echo ""
    TOTAL_SIZE=$(du -sh . | awk '{print $1}')
    echo "总大小: $TOTAL_SIZE"
else
    echo "  (无)"
fi

echo ""

# 验证建议
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}后续步骤${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "1. 验证下载的包："
echo "   cd $DOWNLOAD_DIR"
echo "   rpm -K *.rpm"
echo ""
echo "2. 查看包信息："
echo "   rpm -qip <package-name>.rpm"
echo ""
echo "3. 在离线环境安装："
echo "   rpm -ivh *.rpm"
echo "   或"
echo "   dnf localinstall *.rpm"
echo ""
echo -e "${YELLOW}注意：${NC}某些包可能有依赖关系，建议使用 repotrack 下载完整依赖树"
echo ""

# 退出状态
if [ $FAILED_COUNT -gt 0 ]; then
    exit 1
else
    exit 0
fi
