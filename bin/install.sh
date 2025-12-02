#!/bin/bash

# PostgreSQL 17.6 与 PostGIS 自动编译安装脚本
# 支持 CentOS 7.9, CentOS 8, SteamOS 9 等 RedHat 系列操作系统
# 特点：源码编译安装，支持指定安装目录，避免与系统版本冲突

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 安装配置参数
PREFIX_BASE="/opt/postgresql"
PREFIX_PG="${PREFIX_BASE}/postgres-17.6"
PREFIX_POSTGIS="${PREFIX_PG}"
PREFIX_DEPS="${PREFIX_BASE}/deps"
PG_DATA_DIR="${PREFIX_BASE}/data"
SRC_DIR="/tmp/pg_build"
INSTALLER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOWNLOAD_DIR="${INSTALLER_DIR}/packages"

# 通用版本信息
PG_VERSION="17.6"
POSTGIS_VERSION="3.5.3"
CMAKE_VERSION="4.2.0"
PROJ_VERSION="9.4.0"
GEOS_VERSION="3.12.1"
JSONC_VERSION="0.18-20240915"
SQLITE_VERSION="3.46.0"
BISON_VERSION="3.8.2"
M4_VERSION="1.4.19"
AUTOCONF_VERSION="2.71"
AUTOMAKE_VERSION="1.16.5"
GETTEXT_VERSION="0.21"
BISON_VERSION="3.8.2"

# 已测试CentOS7 依赖，
# 操作系统 前提
# gcc -v 为 4.8.5
CENTOS7_PROJ_VERSION="6.3.2"
CENTOS7_CMAKE_VERSION="3.16.9"
CENTOS7_GEOS_VERSION="3.8.3"

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

pkg_exists() {
    pkg-config --exists "$1" 2>/dev/null
}

select_cmake() {
    if [ -x "${PREFIX_DEPS}/bin/cmake3" ]; then
        CMAKE_BIN="${PREFIX_DEPS}/bin/cmake3"
    elif [ -x "${PREFIX_DEPS}/bin/cmake" ]; then
        CMAKE_BIN="${PREFIX_DEPS}/bin/cmake"
    elif command -v cmake3 &> /dev/null; then
        CMAKE_BIN="cmake3"
    elif command -v cmake &> /dev/null; then
        CMAKE_BIN="cmake"
    else
        echo_error "未找到cmake或cmake3，请安装后重试"
        exit 1
    fi
    echo_info "使用CMake: $CMAKE_BIN ($( $CMAKE_BIN --version | head -n 1 ))" >&2
}

install_cmake_offline() {
    echo_info "正在进行CMake离线安装..."
    local cand1="cmake-${CMAKE_VERSION}.tar.gz"
    local cand2="cmake-${CMAKE_VERSION}.tar.xz"
    local pkg_path=""
    if [ -f "${DOWNLOAD_DIR}/${OS_SHORT}/${cand1}" ]; then
        pkg_path="${DOWNLOAD_DIR}/${OS_SHORT}/${cand1}"
    elif [ -f "${DOWNLOAD_DIR}/${OS_SHORT}/${cand2}" ]; then
        pkg_path="${DOWNLOAD_DIR}/${OS_SHORT}/${cand2}"
    else
        echo_error "错误：未找到离线包 ${cand1} 或 ${cand2}" >&2
        exit 1
    fi

    extract_source "$pkg_path" "$SRC_DIR"
    local src1="${SRC_DIR}/cmake-${CMAKE_VERSION}"
    local src2="${SRC_DIR}/cmake-cmake-${CMAKE_VERSION}"
    local src_dir=""
    if [ -d "$src1" ]; then
        src_dir="$src1"
    elif [ -d "$src2" ]; then
        src_dir="$src2"
    else
        echo_error "错误：未找到CMake源码目录 ${src1} 或 ${src2}" >&2
        exit 1
    fi

    cd "$src_dir"
    ./bootstrap --prefix="${PREFIX_DEPS}" --parallel=$(nproc) || {
        echo_error "配置 CMake 失败"
        exit 1
    }
    make -j$(nproc) || {
        echo_error "编译 CMake 失败"
        exit 1
    }
    make install || {
        echo_error "安装 CMake 失败"
        exit 1
    }
    echo_success "CMake 离线安装完成"
}

install_rpm_offline() {
    local rpm_name="$1"
    local rpm_path="${DOWNLOAD_DIR}/${OS_SHORT}/${rpm_name}"
    if [ ! -f "$rpm_path" ]; then
        if [ -f "${DOWNLOAD_DIR}/${rpm_name}" ]; then
            rpm_path="${DOWNLOAD_DIR}/${rpm_name}"
        else
            echo_error "错误：未找到RPM包 ${rpm_name}"
            echo_info "已查找路径: ${DOWNLOAD_DIR}/${OS_SHORT}/ 与 ${DOWNLOAD_DIR}/"
            echo_info "当前可用文件列表:";
            ls -al "${DOWNLOAD_DIR}/${OS_SHORT}" 2>/dev/null | head -n 200
            exit 1
        fi
    fi
    echo_info "正在安装RPM: ${rpm_name} (路径: ${rpm_path})"
    rpm -Uvh "$rpm_path" || {
        echo_error "安装 ${rpm_name} 失败"
        exit 1
    }
    echo_success "安装完成: ${rpm_name}"
}

ensure_tool_rpm() {
    local tool="$1"
    local rpm="$2"
    if command -v "$tool" >/dev/null 2>&1; then
        echo_success "$tool 已存在，跳过安装"
    else
        install_rpm_offline "$rpm"
    fi
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo_error "请以root用户运行此脚本"
        exit 1
    fi
    echo_success "用户权限检查通过"
}

detect_os() {
    echo_info "正在检测操作系统类型和版本..."
    
    if [ -f /etc/centos-release ]; then
        OS_TYPE="CentOS"
        OS_VERSION=$(cat /etc/centos-release | grep -oP '(\d+\.\d+)' | head -1)
    elif [ -f /etc/redhat-release ]; then
        if grep -q "CentOS" /etc/redhat-release; then
            OS_TYPE="CentOS"
            OS_VERSION=$(cat /etc/redhat-release | grep -oP '(\d+\.\d+)' | head -1)
        else
            OS_TYPE="RHEL"
            OS_VERSION=$(cat /etc/redhat-release | grep -oP '(\d+\.\d+)' | head -1)
        fi
    elif [ -f /etc/os-release ]; then
        OS_TYPE=$(grep -oP '^NAME="?\K[^"]+' /etc/os-release)
        OS_VERSION=$(grep -oP '^VERSION_ID="?\K[^"]+' /etc/os-release)
    else
        echo_error "无法识别操作系统类型"
        exit 1
    fi
    
    if [[ "$OS_TYPE" =~ "CentOS" ]]; then
        OS_TYPE="CentOS"
        if [[ "$OS_VERSION" == "7"* ]]; then
            OS_SHORT="centos7"
        elif [[ "$OS_VERSION" == "8"* ]]; then
            OS_SHORT="centos8"
        elif [[ "$OS_VERSION" == "9"* ]]; then
            OS_SHORT="centos9"
        else
            echo_warning "未测试的CentOS版本: $OS_VERSION，尝试使用通用配置"
            OS_SHORT="centos8"
        fi
    elif [[ "$OS_TYPE" =~ "SteamOS" ]]; then
        OS_TYPE="SteamOS"
        OS_SHORT="steamos9"
    else
        echo_warning "未测试的操作系统类型: $OS_TYPE，尝试使用通用配置"
        if [[ "$OS_VERSION" == "7"* ]]; then
            OS_SHORT="centos7"
        else
            OS_SHORT="centos8"
        fi
    fi
    
    echo_success "操作系统检测完成: $OS_TYPE $OS_VERSION ($OS_SHORT)"
}

apply_override() {
    local base=$1
    local prefix=$2
    local name="${prefix}_${base}"
    local val="${!name}"
    if [ -n "$val" ]; then
        eval "$base=\"$val\""
    fi
}

apply_os_version_overrides() {
    local prefix=""
    case "$OS_SHORT" in
        centos7) prefix="CENTOS7" ;;
        centos8) prefix="CENTOS8" ;;
        centos9) prefix="CENTOS9" ;;
        steamos9) prefix="STEAMOS9" ;;
        *) prefix="" ;;
    esac
    if [ -z "$prefix" ]; then
        return
    fi

    apply_override "PG_VERSION" "$prefix"
    apply_override "POSTGIS_VERSION" "$prefix"
    apply_override "PROJ_VERSION" "$prefix"
    apply_override "GEOS_VERSION" "$prefix"
    apply_override "JSONC_VERSION" "$prefix"
    apply_override "CMAKE_VERSION" "$prefix"
    apply_override "SQLITE_VERSION" "$prefix"
    apply_override "BISON_VERSION" "$prefix"
    apply_override "M4_VERSION" "$prefix"
    apply_override "AUTOCONF_VERSION" "$prefix"
    apply_override "AUTOMAKE_VERSION" "$prefix"
    apply_override "GETTEXT_VERSION" "$prefix"
    apply_override "BISON_VERSION" "$prefix"
}

install_system_deps() {
    echo_info "正在安装基础编译工具和系统依赖..."
    
    # 根据操作系统选择包管理器
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        $PKG_MANAGER install -y gcc gcc-c++ make wget tar bzip2
        
        if [[ "$OS_SHORT" == "centos8" ]]; then
            $PKG_MANAGER config-manager --set-enabled powertools
        elif [[ "$OS_SHORT" == "steamos9" ]]; then
            $PKG_MANAGER config-manager --set-enabled crb
        fi
    else
        PKG_MANAGER="yum"
        $PKG_MANAGER install -y gcc gcc-c++ make wget tar bzip2
    fi
    
    $PKG_MANAGER install -y openssl-devel readline-devel

    if [ ! -x "${PREFIX_DEPS}/bin/cmake3" ] && [ ! -x "${PREFIX_DEPS}/bin/cmake" ]; then
        install_cmake_offline
    fi

    ensure_tool_rpm m4 "$M4_RPM"
    ensure_tool_rpm gettextize "$GETTEXT_RPM"
    ensure_tool_rpm autoconf "$AUTOCONF_RPM"
    ensure_tool_rpm automake "$AUTOMAKE_RPM"
    ensure_tool_rpm bison "$BISON_RPM"
    
    echo_success "基础依赖安装完成"
}

# 创建安装目录和源码目录
prepare_directories() {
    echo_info "正在创建安装目录和源码目录..."
    
    # 创建目录
    mkdir -p "$PREFIX_BASE"
    mkdir -p "$PREFIX_PG"
    mkdir -p "$PREFIX_DEPS"
    mkdir -p "$PG_DATA_DIR"
    mkdir -p "$SRC_DIR"
    mkdir -p "$DOWNLOAD_DIR"
    if [ -n "$OS_SHORT" ]; then
        mkdir -p "$DOWNLOAD_DIR/$OS_SHORT"
    else
        echo_error "无法确定操作系统版本，无法创建系统特定包目录"
        exit 1
    fi
    
    if ! id postgres &> /dev/null; then
        useradd postgres
    fi
    
    # 设置权限
    chown -R postgres:postgres "$PREFIX_BASE"
    chown -R postgres:postgres "$SRC_DIR"
    
    echo_success "目录准备完成"
}

get_offline_package() {
    local package_name=$1
    local output_dir=$2
    
    echo_info "正在检查 $package_name 的离线包..." >&2
    
    if [ -n "$OS_SHORT" ] && [ -f "$output_dir/$OS_SHORT/$package_name" ]; then
        echo "$output_dir/$OS_SHORT/$package_name"
        return 0
    fi
    
    echo_error "错误：未找到离线包 $package_name" >&2
    echo_info "请确保离线包已放置在系统特定目录中：" >&2
    echo_info "$output_dir/$OS_SHORT 目录（packages目录下的系统特定子目录）" >&2
    echo_info "当前系统：$OS_SHORT" >&2
    echo_info "所需文件：$package_name" >&2
    exit 1
}

# 解压源码包
extract_source() {
    local archive=$1
    local target_dir=$2
    
    echo_info "正在解压 $(basename "$archive")..."
    
    case "$archive" in
        *.tar.gz)
            tar -xzf "$archive" -C "$target_dir"
            ;;
        *.tar.xz)
            tar -xJf "$archive" -C "$target_dir"
            ;;
        *.tar.bz2)
            tar -xjf "$archive" -C "$target_dir"
            ;;
        *.zip)
            unzip "$archive" -d "$target_dir"
            ;;
        *)
            echo_error "不支持的压缩格式: $archive"
            return 1
            ;;
    esac
    
    echo_success "解压完成"
}

compile_dependency() {
    local name=$1
    local src_dir=$2
    local config_opts=$3
    
    echo_info "正在编译安装 $name..."
    
    cd "$src_dir"
    
    # 配置
    ./configure --prefix="$PREFIX_DEPS" $config_opts || {
        echo_error "配置 $name 失败"
        return 1
    }
    
    # 编译
    make -j$(nproc) || {
        echo_error "编译 $name 失败"
        return 1
    }
    
    # 安装
    make install || {
        echo_error "安装 $name 失败"
        return 1
    }
    
    echo_success "$name 编译安装完成"
}

install_dependencies() {
    echo_info "开始安装依赖库..."
    
    export PKG_CONFIG_PATH="${PREFIX_DEPS}/lib/pkgconfig:${PKG_CONFIG_PATH}"
    export LD_LIBRARY_PATH="${PREFIX_DEPS}/lib:${LD_LIBRARY_PATH}"
    export PATH="${PREFIX_DEPS}/bin:${PATH}"
    
    if pkg_exists sqlite3 || [ -x "${PREFIX_DEPS}/bin/sqlite3" ]; then
        echo_success "SQLite 已存在，跳过编译安装"
    else
        echo_info "安装SQLite..."
        SQLITE_PACKAGE="sqlite-autoconf-3460000.tar.gz"
        SQLITE_PATH=$(get_offline_package "$SQLITE_PACKAGE" "$DOWNLOAD_DIR")
        extract_source "$SQLITE_PATH" "$SRC_DIR"
        cd "$SRC_DIR/sqlite-autoconf-3460000"
        ./configure --prefix="$PREFIX_DEPS" \
                    --enable-readline=no \
                    --enable-threadsafe=yes || {
            echo_error "配置 SQLite 失败"
            exit 1
        }
        make -j$(nproc) && make install
        echo_success "SQLite 安装完成"
    fi
    
    echo_info "安装JSON-C..."
    if pkg_exists json-c || ls "${PREFIX_DEPS}/lib" 2>/dev/null | grep -q "^libjson-c"; then
        echo_success "JSON-C 已存在，跳过编译安装"
    else
        JSONC_CANDIDATE1="json-c-${JSONC_VERSION}.tar.gz"
        JSONC_CANDIDATE2="json-c-json-c-${JSONC_VERSION}.tar.gz"
        if [ -f "$DOWNLOAD_DIR/$OS_SHORT/$JSONC_CANDIDATE1" ]; then
            JSONC_PATH="$DOWNLOAD_DIR/$OS_SHORT/$JSONC_CANDIDATE1"
        elif [ -f "$DOWNLOAD_DIR/$OS_SHORT/$JSONC_CANDIDATE2" ]; then
            JSONC_PATH="$DOWNLOAD_DIR/$OS_SHORT/$JSONC_CANDIDATE2"
        else
            echo_error "错误：未找到离线包 ${JSONC_CANDIDATE1} 或 ${JSONC_CANDIDATE2}" >&2
            exit 1
        fi
        extract_source "$JSONC_PATH" "$SRC_DIR"
        JSONC_SRC1="$SRC_DIR/json-c-${JSONC_VERSION}"
        JSONC_SRC2="$SRC_DIR/json-c-json-c-${JSONC_VERSION}"
        if [ -d "$JSONC_SRC1" ]; then
            JSONC_SRC="$JSONC_SRC1"
        elif [ -d "$JSONC_SRC2" ]; then
            JSONC_SRC="$JSONC_SRC2"
        else
            echo_error "错误：未找到JSON-C源码目录 ${JSONC_SRC1} 或 ${JSONC_SRC2}" >&2
            exit 1
        fi
        select_cmake
        "$CMAKE_BIN" -S "$JSONC_SRC" -B "$JSONC_SRC/build" \
                     -DCMAKE_INSTALL_PREFIX="$PREFIX_DEPS" \
                     -DCMAKE_BUILD_TYPE=Release \
                     -DBUILD_SHARED_LIBS=ON \
                     -DCMAKE_INSTALL_LIBDIR=lib || {
            echo_error "配置 JSON-C 失败"
            exit 1
        }
        "$CMAKE_BIN" --build "$JSONC_SRC/build" --config Release -- -j$(nproc) || {
            echo_error "编译 JSON-C 失败"
            exit 1
        }
        "$CMAKE_BIN" --install "$JSONC_SRC/build" || {
            echo_error "安装 JSON-C 失败"
            exit 1
        }
        echo_success "JSON-C 安装完成"
    fi
    
    if pkg_exists proj || [ -x "${PREFIX_DEPS}/bin/proj" ] || ls "${PREFIX_DEPS}/lib" 2>/dev/null | grep -q "^libproj"; then
        echo_success "PROJ 已存在，跳过编译安装"
    else
        echo_info "安装PROJ..."
        PROJ_SELECTED_VERSION="$PROJ_VERSION"
        PROJ_PACKAGE="proj-${PROJ_SELECTED_VERSION}.tar.gz"
        PROJ_PATH=$(get_offline_package "$PROJ_PACKAGE" "$DOWNLOAD_DIR")
        extract_source "$PROJ_PATH" "$SRC_DIR"
        select_cmake
        "$CMAKE_BIN" -S "$SRC_DIR/proj-${PROJ_SELECTED_VERSION}" -B "$SRC_DIR/proj-${PROJ_SELECTED_VERSION}/build" \
                     -DCMAKE_INSTALL_PREFIX="$PREFIX_DEPS" \
                     -DCMAKE_BUILD_TYPE=Release \
                     -DBUILD_SHARED_LIBS=ON \
                     -DCMAKE_INSTALL_LIBDIR=lib \
                     -DCMAKE_PREFIX_PATH="$PREFIX_DEPS" \
                     -DBUILD_TESTING=OFF \
                     -DPROJ_TESTS=OFF || {
            echo_error "配置 PROJ 失败"
            exit 1
        }
        "$CMAKE_BIN" --build "$SRC_DIR/proj-${PROJ_SELECTED_VERSION}/build" --config Release -- -j$(nproc) || {
            echo_error "编译 PROJ 失败"
            exit 1
        }
        "$CMAKE_BIN" --install "$SRC_DIR/proj-${PROJ_SELECTED_VERSION}/build" || {
            echo_error "安装 PROJ 失败"
            exit 1
        }
        echo_success "PROJ 安装完成"
    fi
    
    if [ -x "${PREFIX_DEPS}/bin/geos-config" ] || ls "${PREFIX_DEPS}/lib" 2>/dev/null | grep -q "^libgeos"; then
        echo_success "GEOS 已存在，跳过编译安装"
    else
        echo_info "安装GEOS..."
        GEOS_CANDIDATE1="geos-${GEOS_VERSION}.tar.bz2"
        GEOS_CANDIDATE2="geos-${GEOS_VERSION}.tar.gz"
        if [ -f "$DOWNLOAD_DIR/$OS_SHORT/$GEOS_CANDIDATE1" ]; then
            GEOS_PATH="$DOWNLOAD_DIR/$OS_SHORT/$GEOS_CANDIDATE1"
        elif [ -f "$DOWNLOAD_DIR/$OS_SHORT/$GEOS_CANDIDATE2" ]; then
            GEOS_PATH="$DOWNLOAD_DIR/$OS_SHORT/$GEOS_CANDIDATE2"
        else
            echo_error "错误：未找到离线包 ${GEOS_CANDIDATE1} 或 ${GEOS_CANDIDATE2}" >&2
            exit 1
        fi
        extract_source "$GEOS_PATH" "$SRC_DIR"
        select_cmake
        "$CMAKE_BIN" -S "$SRC_DIR/geos-${GEOS_VERSION}" -B "$SRC_DIR/geos-${GEOS_VERSION}/build" \
                     -DCMAKE_INSTALL_PREFIX="$PREFIX_DEPS" \
                     -DCMAKE_BUILD_TYPE=Release \
                     -DBUILD_SHARED_LIBS=ON \
                     -DCMAKE_INSTALL_LIBDIR=lib || {
            echo_error "配置 GEOS 失败"
            exit 1
        }
        "$CMAKE_BIN" --build "$SRC_DIR/geos-${GEOS_VERSION}/build" --config Release -- -j$(nproc) || {
            echo_error "编译 GEOS 失败"
            exit 1
        }
        "$CMAKE_BIN" --install "$SRC_DIR/geos-${GEOS_VERSION}/build" || {
            echo_error "安装 GEOS 失败"
            exit 1
        }
        echo_success "GEOS 安装完成"
    fi
    
    echo_success "所有依赖库安装完成"
}

# 安装PostgreSQL
install_postgresql() {
    echo_info "开始安装PostgreSQL ${PG_VERSION}..."
    
    PG_PACKAGE="postgresql-${PG_VERSION}.tar.bz2"
    PG_PATH=$(get_offline_package "$PG_PACKAGE" "$DOWNLOAD_DIR")
    extract_source "$PG_PATH" "$SRC_DIR"
    
    cd "$SRC_DIR/postgresql-${PG_VERSION}"
    
    export PATH="${PREFIX_DEPS}/bin:${PATH}"
    CFLAGS="-I$PREFIX_DEPS/include" \
    LDFLAGS="-L$PREFIX_DEPS/lib -Wl,-rpath,$PREFIX_DEPS/lib" \
    ./configure --prefix="$PREFIX_PG" \
                --with-openssl \
                --with-readline \
                --without-icu \
                --without-libxml \
                --without-bonjour \
                --without-gssapi \
                --without-ldap \
                --without-pam \
                --without-krb5 \
                --without-selinux \
                || {
        echo_error "配置 PostgreSQL 失败"
        exit 1
    }
    
    # 编译
    make -j$(nproc) world || {
        echo_error "编译 PostgreSQL 失败"
        exit 1
    }
    
    # 安装
    make install-world || {
        echo_error "安装 PostgreSQL 失败"
        exit 1
    }
    
    echo_success "PostgreSQL ${PG_VERSION} 安装完成"
}

# 安装PostGIS
install_postgis() {
    echo_info "开始安装PostGIS ${POSTGIS_VERSION}..."
    
    # 使用系统特定目录中的离线源码
    POSTGIS_PACKAGE="postgis-${POSTGIS_VERSION}.tar.gz"
    POSTGIS_PATH=$(get_offline_package "$POSTGIS_PACKAGE" "$DOWNLOAD_DIR")
    extract_source "$POSTGIS_PATH" "$SRC_DIR"
    
    cd "$SRC_DIR/postgis-${POSTGIS_VERSION}"
    
    # 配置环境变量，确保使用我们自己编译的库
    export PKG_CONFIG_PATH="${PREFIX_DEPS}/lib/pkgconfig:${PKG_CONFIG_PATH}"
    export PATH="${PREFIX_PG}/bin:${PREFIX_DEPS}/bin:${PATH}"
    
    # 配置PostGIS，指定PostgreSQL和依赖路径，确保完全使用我们自己编译的库
    CFLAGS="-I$PREFIX_PG/include -I$PREFIX_DEPS/include" \
    LDFLAGS="-L$PREFIX_PG/lib -L$PREFIX_DEPS/lib -Wl,-rpath,$PREFIX_PG/lib -Wl,-rpath,$PREFIX_DEPS/lib" \
    ./configure --prefix="$PREFIX_POSTGIS" \
                --with-pgconfig="$PREFIX_PG/bin/pg_config" \
                --with-geosconfig="$PREFIX_DEPS/bin/geos-config" \
                --with-projdir="$PREFIX_DEPS" \
                --with-proj-include="$PREFIX_DEPS/include" \
                --with-proj-lib="$PREFIX_DEPS/lib" \
                --with-jsondir="$PREFIX_DEPS" \
                --without-raster \
                --without-topology \
                --without-gui \
                --without-interrupt-tests || {
        echo_error "配置 PostGIS 失败"
        exit 1
    }
    
    # 编译
    make -j$(nproc) || {
        echo_error "编译 PostGIS 失败"
        exit 1
    }
    
    # 安装
    make install || {
        echo_error "安装 PostGIS 失败"
        exit 1
    }
    
    # 安装扩展脚本
    make install-extension || {
        echo_warning "安装 PostGIS 扩展脚本失败，但不影响基本功能"
    }
    
    echo_success "PostGIS ${POSTGIS_VERSION} 安装完成"
}

# 配置动态库加载路径
configure_ldconfig() {
    echo_info "正在配置动态库加载路径..."
    
    # 创建或更新ld.so.conf.d文件
    cat > /etc/ld.so.conf.d/postgresql-custom.conf << EOF
${PREFIX_DEPS}/lib
${PREFIX_PG}/lib
EOF
    
    # 更新ldconfig缓存
    ldconfig
    
    echo_success "动态库加载路径配置完成"
}

# 初始化PostgreSQL数据库
initialize_postgresql() {
    echo_info "正在初始化PostgreSQL数据库..."
    
    # 确保数据目录为空
    if [ -d "$PG_DATA_DIR" ] && [ "$(ls -A "$PG_DATA_DIR" 2>/dev/null)" ]; then
        echo_warning "数据目录 $PG_DATA_DIR 不为空，跳过初始化"
        return 0
    fi
    
    # 使用postgres用户初始化数据库
    su - postgres -c "$PREFIX_PG/bin/initdb -D '$PG_DATA_DIR'"
    
    echo_success "PostgreSQL数据库初始化完成"
}

# 配置PostgreSQL
configure_postgresql() {
    echo_info "正在配置PostgreSQL..."
    
    # 复制配置文件
    CONFIG_DIR="$(cd "$(dirname "$0")/../config" && pwd)"
    if [ -f "$CONFIG_DIR/postgresql.conf.template" ]; then
        cp "$CONFIG_DIR/postgresql.conf.template" "$PG_DATA_DIR/postgresql.conf"
    else
        echo_warning "配置模板不存在，修改默认配置"
        # 修改默认配置
        sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" "$PG_DATA_DIR/postgresql.conf"
        sed -i "s/#password_encryption = scram-sha-256/password_encryption = scram-sha-256/g" "$PG_DATA_DIR/postgresql.conf"
        
        # 添加扩展库路径
        echo "dynamic_library_path = '$PREFIX_PG/lib/postgresql'" >> "$PG_DATA_DIR/postgresql.conf"
    fi
    
    # 配置认证
    if [ -f "$CONFIG_DIR/pg_hba.conf.template" ]; then
        cp "$CONFIG_DIR/pg_hba.conf.template" "$PG_DATA_DIR/pg_hba.conf"
    else
        echo_warning "认证模板不存在，修改默认配置"
        # 修改pg_hba.conf允许远程连接
        echo "host    all             all             0.0.0.0/0               scram-sha-256" >> "$PG_DATA_DIR/pg_hba.conf"
    fi
    
    # 设置权限
    chown -R postgres:postgres "$PG_DATA_DIR"
    chmod 700 "$PG_DATA_DIR"
    
    echo_success "PostgreSQL配置完成"
}

# 创建systemd服务文件
create_systemd_service() {
    echo_info "正在创建systemd服务文件..."
    
    # 创建服务文件
    cat > /usr/lib/systemd/system/postgresql-custom.service << EOF
[Unit]
Description=PostgreSQL Custom Database Server
After=network.target

[Service]
Type=forking
User=postgres
Environment=PGDATA=${PG_DATA_DIR}
Environment=LD_LIBRARY_PATH=${PREFIX_DEPS}/lib:${PREFIX_PG}/lib
ExecStart=${PREFIX_PG}/bin/pg_ctl start -D \${PGDATA} -s -o "-p 5432"
ExecStop=${PREFIX_PG}/bin/pg_ctl stop -D \${PGDATA} -s -m fast
ExecReload=${PREFIX_PG}/bin/pg_ctl reload -D \${PGDATA} -s

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd
    systemctl daemon-reload
    
    echo_success "systemd服务文件创建完成"
}

# 启动PostgreSQL服务
start_postgresql() {
    echo_info "正在启动PostgreSQL服务..."
    
    # 启动服务并设置自启动
    systemctl start postgresql-custom
    systemctl enable postgresql-custom
    
    # 检查服务状态
    if systemctl is-active --quiet postgresql-custom; then
        echo_success "PostgreSQL服务启动成功"
    else
        echo_error "PostgreSQL服务启动失败，请检查日志"
        exit 1
    fi
}

# 配置环境变量
configure_environment() {
    echo_info "正在配置环境变量..."
    
    # 创建环境变量文件
    cat > /etc/profile.d/postgresql-custom.sh << EOF
# PostgreSQL Custom Environment Variables
export PATH=${PREFIX_PG}/bin:\$PATH
export LD_LIBRARY_PATH=${PREFIX_DEPS}/lib:${PREFIX_PG}/lib:\$LD_LIBRARY_PATH
export PGDATA=${PG_DATA_DIR}
EOF
    
    # 立即加载环境变量
    source /etc/profile.d/postgresql-custom.sh
    
    echo_success "环境变量配置完成"
}

# 配置PostGIS
enable_postgis() {
    echo_info "正在配置PostGIS扩展..."
    
    # 等待PostgreSQL启动
    sleep 5
    
    # 设置环境变量
    export PATH="${PREFIX_PG}/bin:$PATH"
    export LD_LIBRARY_PATH="${PREFIX_DEPS}/lib:${PREFIX_PG}/lib:$LD_LIBRARY_PATH"
    
    # 创建扩展
    su - postgres -c "$PREFIX_PG/bin/psql -c 'CREATE EXTENSION IF NOT EXISTS postgis;'"
    su - postgres -c "$PREFIX_PG/bin/psql -c 'CREATE EXTENSION IF NOT EXISTS postgis_topology;'"
    
    # 验证PostGIS安装
    POSTGIS_VERSION=$(su - postgres -c "$PREFIX_PG/bin/psql -t -c 'SELECT postgis_version();' 2>/dev/null")
    if [ -n "$POSTGIS_VERSION" ]; then
        echo_success "PostGIS配置完成，版本: $POSTGIS_VERSION"
    else
        echo_error "PostGIS配置失败，请检查是否正确安装"
    fi
}

# 配置防火墙
configure_firewall() {
    echo_info "正在配置防火墙..."
    
    # 检查防火墙是否运行
    if command -v firewall-cmd &> /dev/null && firewall-cmd --state &> /dev/null; then
        # 永久开放5432端口
        firewall-cmd --permanent --add-port=5432/tcp
        firewall-cmd --reload
        echo_success "防火墙配置完成"
    else
        echo_warning "firewalld未运行，跳过防火墙配置"
    fi
}

# 设置PostgreSQL密码
set_postgres_password() {
    echo_info "正在设置PostgreSQL密码..."
    
    # 提示用户输入密码
    read -s -p "请输入PostgreSQL的postgres用户密码: " PGPASSWORD
    echo
    
    # 设置密码
    su - postgres -c "$PREFIX_PG/bin/psql -c \"ALTER USER postgres WITH PASSWORD '$PGPASSWORD';\""
    
    echo_success "PostgreSQL密码设置完成"
}

# 清理临时文件
cleanup() {
    echo_info "正在清理临时文件..."
    
    # 删除源码目录
    rm -rf "$SRC_DIR"
    
    echo_success "清理完成"
}

# 显示安装信息
display_info() {
    echo_success "\n======================================="
    echo_success "PostgreSQL ${PG_VERSION} 和 PostGIS ${POSTGIS_VERSION} 编译安装完成！"
    echo_success "======================================="
    echo_info "安装目录: $PREFIX_PG"
    echo_info "数据目录: $PG_DATA_DIR"
    echo_info "依赖目录: $PREFIX_DEPS"
    echo_info "服务名称: postgresql-custom"
    echo_info "端口: 5432"
    echo_info ""
    echo_info "连接命令: $PREFIX_PG/bin/psql -U postgres -h localhost"
    echo_info "服务控制: systemctl [start|stop|restart|status] postgresql-custom"
    echo_info ""
    echo_warning "注意：请重新登录或执行 'source /etc/profile.d/postgresql-custom.sh' 以加载环境变量"
    echo_success "======================================="
}

# 主函数
main() {
    echo_info "开始编译安装PostgreSQL ${PG_VERSION} 和 PostGIS ${POSTGIS_VERSION}..."
    
    # 执行各个步骤
    check_root
    detect_os
    apply_os_version_overrides
    install_system_deps
    prepare_directories
    install_dependencies
    install_postgresql
    install_postgis
    configure_ldconfig
    initialize_postgresql
    configure_postgresql
    create_systemd_service
    start_postgresql
    configure_environment
    enable_postgis
    configure_firewall
    set_postgres_password
    # cleanup
    display_info
}

# 执行主函数
main
