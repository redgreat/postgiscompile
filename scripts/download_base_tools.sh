#!/bin/bash
# Rocky Linux 9 基础编译工具下载脚本
# 包含: gcc, gcc-c++, make, tar, bzip2, xz

set -e

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOWNLOAD_DIR="${PROJECT_ROOT}/packages/rockylinux9/rpm_base"
BASE_URL="https://dl.rockylinux.org/vault/rocky/9.6"

# 创建下载目录
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

echo "下载目录: $DOWNLOAD_DIR"
echo "正在下载基础系统工具..."

# 1. BaseOS 仓库工具 (tar, bzip2, xz, make)
# 注意：版本号基于 Rocky Linux 9.6

# tar (BaseOS)
wget -c "${BASE_URL}/BaseOS/x86_64/os/Packages/t/tar-1.34-7.el9.x86_64.rpm"

# bzip2 (BaseOS)
wget -c "${BASE_URL}/BaseOS/x86_64/os/Packages/b/bzip2-1.0.8-10.el9_5.x86_64.rpm"

# xz (BaseOS)
wget -c "${BASE_URL}/BaseOS/x86_64/os/Packages/x/xz-5.2.5-8.el9_0.x86_64.rpm"

# make (BaseOS)
wget -c "${BASE_URL}/BaseOS/x86_64/os/Packages/m/make-4.3-8.el9.x86_64.rpm"

# 2. AppStream 仓库工具 (gcc)

# gcc (AppStream)
wget -c "${BASE_URL}/AppStream/x86_64/os/Packages/g/gcc-11.5.0-5.el9_5.x86_64.rpm"

# gcc-c++ (AppStream)
wget -c "${BASE_URL}/AppStream/x86_64/os/Packages/g/gcc-c++-11.5.0-5.el9_5.x86_64.rpm"

echo ""
echo "下载完成！"
echo "文件保存在: $DOWNLOAD_DIR"
echo ""
echo "注意：安装 gcc 可能还需要 glibc-devel, kernel-headers 等依赖包。"
echo "如果安装时提示缺少依赖，请使用 'dnf download --resolve' 在联网机器上下载完整依赖树。"
