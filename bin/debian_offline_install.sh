#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALLER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES_DIR="${INSTALLER_DIR}/packages"

PG_MAJOR="17"
POSTGIS_MAJOR="3"

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

## 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo_error "请以root用户运行此脚本"
        exit 1
    fi
}

## 解析Debian版本
detect_debian() {
    if [ ! -f /etc/os-release ]; then
        echo_error "未检测到 /etc/os-release，非Debian系统"
        exit 1
    fi

    DEBIAN_VERSION_ID=$(grep -oP '^VERSION_ID="?\K[^" ]+' /etc/os-release)
    DEBIAN_NAME=$(grep -oP '^ID="?\K[^" ]+' /etc/os-release)

    if [ "${DEBIAN_NAME}" != "debian" ]; then
        echo_error "当前系统不是Debian"
        exit 1
    fi

    case "${DEBIAN_VERSION_ID}" in
        12)
            OS_SHORT="debian12"
            CODENAME="bookworm"
            ;;
        13)
            OS_SHORT="debian13"
            CODENAME="trixie"
            ;;
        14)
            OS_SHORT="debian14"
            CODENAME="forky"
            ;;
        *)
            echo_error "不支持的Debian版本: ${DEBIAN_VERSION_ID}"
            exit 1
            ;;
    esac

    echo_success "检测到 Debian ${DEBIAN_VERSION_ID} (${CODENAME})"
}

## 准备目录结构
prepare_directories() {
    mkdir -p "${PACKAGES_DIR}/${OS_SHORT}"
    echo_success "已准备目录: ${PACKAGES_DIR}/${OS_SHORT}"
}

## 添加PGDG软件源
add_pgdg_repo() {
    if [ ! -f /etc/apt/keyrings/postgresql.asc ]; then
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /etc/apt/keyrings/postgresql.asc
    fi

    echo "deb [signed-by=/etc/apt/keyrings/postgresql.asc] http://apt.postgresql.org/pub/repos/apt ${CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    apt-get update -y
}

## 下载所需deb包到版本目录
download_packages() {
    local target_dir="${PACKAGES_DIR}/${OS_SHORT}"

    apt-get install -y apt-transport-https ca-certificates gnupg curl
    add_pgdg_repo

    local -a pkgs
    pkgs=(
        "postgresql-${PG_MAJOR}"
        "postgresql-client-${PG_MAJOR}"
        "postgresql-contrib-${PG_MAJOR}"
        "postgresql-${PG_MAJOR}-postgis-${POSTGIS_MAJOR}"
        "postgis"
    )

    apt-get -y -o Dir::Cache::archives="${target_dir}" install --download-only "${pkgs[@]}"

    (cd "${target_dir}" && ls -1 *.deb > packages_list.txt || true)
    echo_success "已下载deb包到: ${target_dir}"
}

## 离线安装本地deb包
install_from_local() {
    local source_dir="${PACKAGES_DIR}/${OS_SHORT}"

    if [ ! -d "${source_dir}" ]; then
        echo_error "未找到本地包目录: ${source_dir}"
        exit 1
    fi

    apt-get install -y apt-transport-https ca-certificates
    apt-get update -y || true

    apt install -y --no-install-recommends "${source_dir}"/*.deb
    echo_success "离线安装完成"
}

## 启用PostGIS扩展
enable_postgis() {
    systemctl start postgresql || true
    sleep 3
    sudo -u postgres psql -t -c 'CREATE EXTENSION IF NOT EXISTS postgis;' || true
    sudo -u postgres psql -t -c 'CREATE EXTENSION IF NOT EXISTS postgis_topology;' || true
    echo_success "PostGIS扩展已尝试启用"
}

## 使用说明
usage() {
    echo "用法: $0 [download|install]"
    echo "download: 在线主机下载deb包到 ${PACKAGES_DIR}/<debianXX>"
    echo "install : 离线主机从本地目录安装PostgreSQL+PostGIS"
}

## 主函数
main() {
    local action="$1"
    if [ -z "${action}" ]; then
        usage
        exit 1
    fi

    check_root
    detect_debian
    prepare_directories

    case "${action}" in
        download)
            download_packages
            ;;
        install)
            install_from_local
            enable_postgis
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"

