#!/bin/bash

# PostgreSQL 18 与 PostGIS 3.6.0 自动编译安装脚本 - Rocky Linux 9 专用版
# 基于 Rocky Linux 9 的稳定系统,全离线安装
# 依赖包优先使用 RPM,无 RPM 则编译安装
# 版本适配参考: https://trac.osgeo.org/postgis/wiki/UsersWikiPostgreSQLPostGIS

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 安装配置参数
PREFIX_BASE="/opt/postgresql"
PREFIX_PG="${PREFIX_BASE}/postgres-18"
PREFIX_POSTGIS="${PREFIX_PG}"
PREFIX_DEPS="${PREFIX_BASE}/deps"
PG_DATA_DIR="${PREFIX_BASE}/data"
SRC_DIR="/tmp/pg_build"
INSTALLER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOWNLOAD_DIR="${INSTALLER_DIR}/packages"
OS_SHORT="rockylinux9"

# Rocky Linux 9 版本信息 (基于最新稳定版本)
# 参考: https://trac.osgeo.org/postgis/wiki/UsersWikiPostgreSQLPostGIS
PG_VERSION="18.1"
POSTGIS_VERSION="3.6.0"
GEOS_VERSION="3.14.0"
PROJ_VERSION="9.7.0"
GDAL_VERSION="3.11.4"
SFCGAL_VERSION="2.2.0"
PROTOBUF_C_VERSION="1.5.2"
JSONC_VERSION="0.18-20240915"
SQLITE_VERSION="3.46.0"
CMAKE_VERSION="3.31.3"

# 编译工具版本
BISON_VERSION="3.8.2"
M4_VERSION="1.4.19"
AUTOCONF_VERSION="2.71"
AUTOMAKE_VERSION="1.16.5"
GETTEXT_VERSION="0.22.5"

# RPM 包名称 (Rocky Linux 9 可用的系统包)
M4_RPM="m4-1.4.19-1.el9.x86_64.rpm"
GETTEXT_RPM="gettext-0.21-8.el9.x86_64.rpm"
AUTOCONF_RPM="autoconf-2.71-3.el9.noarch.rpm"
AUTOMAKE_RPM="automake-1.16.5-11.el9.noarch.rpm"
BISON_RPM="bison-3.7.4-5.el9.x86_64.rpm"

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

# 检查包是否存在
pkg_exists() {
    pkg-config --exists "$1" 2>/dev/null
}

# 选择 CMake 版本
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

# 离线安装 CMake
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

# 离线安装 RPM 包
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
    rpm -Uvh "$rpm_path" --nodeps --force || {
        echo_error "安装 ${rpm_name} 失败"
        exit 1
    }
    echo_success "安装完成: ${rpm_name}"
}

# 确保工具存在，优先使用 RPM
ensure_tool_rpm() {
    local tool="$1"
    local rpm="$2"
    if command -v "$tool" > /dev/null 2>&1; then
        echo_success "$tool 已存在，跳过安装"
    else
        install_rpm_offline "$rpm"
    fi
}

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo_error "请以root用户运行此脚本"
        exit 1
    fi
    echo_success "用户权限检查通过"
}

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
    
    if [[ "$OS_TYPE" =~ "Rocky Linux" ]]; then
        if [[ "$OS_VERSION" == "9"* ]]; then
            echo_success "操作系统检测完成: Rocky Linux $OS_VERSION"
        else
            echo_warning "此脚本专为 Rocky Linux 9 设计，当前版本: $OS_VERSION"
            read -p "是否继续安装? (y/n): " confirm
            if [[ "$confirm" != "y" ]]; then
                exit 1
            fi
        fi
    else
        echo_warning "此脚本专为 Rocky Linux 9 设计，当前系统: $OS_TYPE"
        read -p "是否继续安装? (y/n): " confirm
        if [[ "$confirm" != "y" ]]; then
            exit 1
        fi
    fi
}

# 安装系统依赖
install_system_deps() {
    echo_info "正在安装基础编译工具和系统依赖..."
    
    # Rocky Linux 9 使用 dnf
    PKG_MANAGER="dnf"
    
    # 启用 CRB (CodeReady Builder) 仓库 - 类似 CentOS 8 的 PowerTools
    echo_info "启用 CRB 仓库..."
    $PKG_MANAGER config-manager --set-enabled crb || {
        echo_warning "启用 CRB 仓库失败，尝试继续..."
    }
    
    # 安装基础编译工具
    echo_info "安装基础编译工具..."
    $PKG_MANAGER install -y gcc gcc-c++ make wget tar bzip2 xz || {
        echo_error "安装基础编译工具失败"
        exit 1
    }
    
    # 安装系统开发库
    echo_info "安装系统开发库..."
    $PKG_MANAGER install -y openssl-devel readline-devel zlib-devel || {
        echo_error "安装系统开发库失败"
        exit 1
    }
    
    # 安装 CMake (如果本地没有)
    if [ ! -x "${PREFIX_DEPS}/bin/cmake3" ] && [ ! -x "${PREFIX_DEPS}/bin/cmake" ]; then
        install_cmake_offline
    fi

    # 安装编译工具 (优先使用 RPM)
    ensure_tool_rpm m4 "$M4_RPM"
    ensure_tool_rpm gettextize "$GETTEXT_RPM"
    ensure_tool_rpm autoconf "$AUTOCONF_RPM"
    ensure_tool_rpm automake "$AUTOMAKE_RPM"
    ensure_tool_rpm bison "$BISON_RPM"
    
    echo_success "基础依赖安装完成"
}

# 创建安装目录
prepare_directories() {
    echo_info "正在创建安装目录和源码目录..."
    
    # 创建目录
    mkdir -p "$PREFIX_BASE"
    mkdir -p "$PREFIX_PG"
    mkdir -p "$PREFIX_DEPS"
    mkdir -p "$PG_DATA_DIR"
    mkdir -p "$SRC_DIR"
    mkdir -p "$DOWNLOAD_DIR/$OS_SHORT"
    
    # 创建 postgres 用户
    if ! id postgres &> /dev/null; then
        useradd -r -s /bin/bash postgres
    fi
    
    # 设置权限
    chown -R postgres:postgres "$PREFIX_BASE"
    chown -R postgres:postgres "$SRC_DIR"
    
    echo_success "目录准备完成"
}

# 获取离线包路径
get_offline_package() {
    local package_name=$1
    local output_dir=$2
    
    echo_info "正在检查 $package_name 的离线包..." >&2
    
    if [ -f "$output_dir/$OS_SHORT/$package_name" ]; then
        echo "$output_dir/$OS_SHORT/$package_name"
        return 0
    fi
    
    echo_error "错误：未找到离线包 $package_name" >&2
    echo_info "请确保离线包已放置在：$output_dir/$OS_SHORT/" >&2
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

# 安装依赖库
install_dependencies() {
    echo_info "开始安装依赖库..."
    
    export PKG_CONFIG_PATH="${PREFIX_DEPS}/lib/pkgconfig:${PKG_CONFIG_PATH}"
    export LD_LIBRARY_PATH="${PREFIX_DEPS}/lib:${LD_LIBRARY_PATH}"
    export PATH="${PREFIX_DEPS}/bin:${PATH}"
    
    # 1. 安装 SQLite
    if pkg_exists sqlite3 || [ -x "${PREFIX_DEPS}/bin/sqlite3" ]; then
        echo_success "SQLite 已存在，跳过编译安装"
    else
        echo_info "安装 SQLite ${SQLITE_VERSION}..."
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
    
    # 2. 安装 JSON-C
    if pkg_exists json-c || ls "${PREFIX_DEPS}/lib" 2>/dev/null | grep -q "^libjson-c"; then
        echo_success "JSON-C 已存在，跳过编译安装"
    else
        echo_info "安装 JSON-C ${JSONC_VERSION}..."
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
            echo_error "错误：未找到JSON-C源码目录" >&2
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
    
    # 3. 安装 PROJ
    if pkg_exists proj || [ -x "${PREFIX_DEPS}/bin/proj" ]; then
        echo_success "PROJ 已存在，跳过编译安装"
    else
        echo_info "安装 PROJ ${PROJ_VERSION}..."
        PROJ_PACKAGE="proj-${PROJ_VERSION}.tar.gz"
        PROJ_PATH=$(get_offline_package "$PROJ_PACKAGE" "$DOWNLOAD_DIR")
        extract_source "$PROJ_PATH" "$SRC_DIR"
        select_cmake
        "$CMAKE_BIN" -S "$SRC_DIR/proj-${PROJ_VERSION}" -B "$SRC_DIR/proj-${PROJ_VERSION}/build" \
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
        "$CMAKE_BIN" --build "$SRC_DIR/proj-${PROJ_VERSION}/build" --config Release -- -j$(nproc) || {
            echo_error "编译 PROJ 失败"
            exit 1
        }
        "$CMAKE_BIN" --install "$SRC_DIR/proj-${PROJ_VERSION}/build" || {
            echo_error "安装 PROJ 失败"
            exit 1
        }
        echo_success "PROJ 安装完成"
    fi
    
    # 4. 安装 GEOS
    if [ -x "${PREFIX_DEPS}/bin/geos-config" ]; then
        echo_success "GEOS 已存在，跳过编译安装"
    else
        echo_info "安装 GEOS ${GEOS_VERSION}..."
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
    
    # 5. 安装 protobuf-c (PostGIS 3.6 需要)
    if pkg_exists libprotobuf-c || ls "${PREFIX_DEPS}/lib" 2>/dev/null | grep -q "^libprotobuf-c"; then
        echo_success "protobuf-c 已存在，跳过编译安装"
    else
        echo_info "安装 protobuf-c ${PROTOBUF_C_VERSION}..."
        PROTOBUF_C_PACKAGE="protobuf-c-${PROTOBUF_C_VERSION}.tar.gz"
        PROTOBUF_C_PATH=$(get_offline_package "$PROTOBUF_C_PACKAGE" "$DOWNLOAD_DIR")
        extract_source "$PROTOBUF_C_PATH" "$SRC_DIR"
        cd "$SRC_DIR/protobuf-c-${PROTOBUF_C_VERSION}"
        ./configure --prefix="$PREFIX_DEPS" || {
            echo_error "配置 protobuf-c 失败"
            exit 1
        }
        make -j$(nproc) || {
            echo_error "编译 protobuf-c 失败"
            exit 1
        }
        make install || {
            echo_error "安装 protobuf-c 失败"
            exit 1
        }
        echo_success "protobuf-c 安装完成"
    fi
    
    echo_success "所有依赖库安装完成"
}

# 安装 PostgreSQL
install_postgresql() {
    echo_info "开始安装 PostgreSQL ${PG_VERSION}..."
    
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

# 安装 PostGIS
install_postgis() {
    echo_info "开始安装 PostGIS ${POSTGIS_VERSION}..."
    
    POSTGIS_PACKAGE="postgis-${POSTGIS_VERSION}.tar.gz"
    POSTGIS_PATH=$(get_offline_package "$POSTGIS_PACKAGE" "$DOWNLOAD_DIR")
    extract_source "$POSTGIS_PATH" "$SRC_DIR"
    
    cd "$SRC_DIR/postgis-${POSTGIS_VERSION}"
    
    # 配置环境变量
    export PKG_CONFIG_PATH="${PREFIX_DEPS}/lib/pkgconfig:${PKG_CONFIG_PATH}"
    export PATH="${PREFIX_PG}/bin:${PREFIX_DEPS}/bin:${PATH}"
    
    # 配置 PostGIS
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
    
    cat > /etc/ld.so.conf.d/postgresql-custom.conf <<EOF
${PREFIX_DEPS}/lib
${PREFIX_PG}/lib
EOF
    
    ldconfig
    
    echo_success "动态库加载路径配置完成"
}

# 初始化 PostgreSQL 数据库
initialize_postgresql() {
    echo_info "正在初始化 PostgreSQL 数据库..."
    
    if [ -d "$PG_DATA_DIR" ] && [ "$(ls -A "$PG_DATA_DIR" 2>/dev/null)" ]; then
        echo_warning "数据目录 $PG_DATA_DIR 不为空，跳过初始化"
        return 0
    fi
    
    su - postgres -c "$PREFIX_PG/bin/initdb -D '$PG_DATA_DIR'"
    
    echo_success "PostgreSQL 数据库初始化完成"
}

# 配置 PostgreSQL
configure_postgresql() {
    echo_info "正在配置 PostgreSQL..."
    
    CONFIG_DIR="$(cd "$(dirname "$0")/../config" && pwd)"
    if [ -f "$CONFIG_DIR/postgresql.conf.template" ]; then
        cp "$CONFIG_DIR/postgresql.conf.template" "$PG_DATA_DIR/postgresql.conf"
    else
        echo_warning "配置模板不存在，修改默认配置"
        sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" "$PG_DATA_DIR/postgresql.conf"
        sed -i "s/#password_encryption = scram-sha-256/password_encryption = scram-sha-256/g" "$PG_DATA_DIR/postgresql.conf"
        echo "dynamic_library_path = '$PREFIX_PG/lib/postgresql'" >> "$PG_DATA_DIR/postgresql.conf"
    fi
    
    if [ -f "$CONFIG_DIR/pg_hba.conf.template" ]; then
        cp "$CONFIG_DIR/pg_hba.conf.template" "$PG_DATA_DIR/pg_hba.conf"
    else
        echo_warning "认证模板不存在，修改默认配置"
        echo "host    all             all             0.0.0.0/0               scram-sha-256" >> "$PG_DATA_DIR/pg_hba.conf"
    fi
    
    chown -R postgres:postgres "$PG_DATA_DIR"
    chmod 700 "$PG_DATA_DIR"
    
    echo_success "PostgreSQL 配置完成"
}

# 创建 systemd 服务文件
create_systemd_service() {
    echo_info "正在创建 systemd 服务文件..."
    
    cat > /usr/lib/systemd/system/postgresql-custom.service <<EOF
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
    
    systemctl daemon-reload
    
    echo_success "systemd 服务文件创建完成"
}

# 启动 PostgreSQL 服务
start_postgresql() {
    echo_info "正在启动 PostgreSQL 服务..."
    
    systemctl start postgresql-custom
    systemctl enable postgresql-custom
    
    if systemctl is-active --quiet postgresql-custom; then
        echo_success "PostgreSQL 服务启动成功"
    else
        echo_error "PostgreSQL 服务启动失败，请检查日志"
        exit 1
    fi
}

# 配置环境变量
configure_environment() {
    echo_info "正在配置环境变量..."
    
    cat > /etc/profile.d/postgresql-custom.sh <<EOF
# PostgreSQL Custom Environment Variables
export PATH=${PREFIX_PG}/bin:\$PATH
export LD_LIBRARY_PATH=${PREFIX_DEPS}/lib:${PREFIX_PG}/lib:\$LD_LIBRARY_PATH
export PGDATA=${PG_DATA_DIR}
EOF
    
    source /etc/profile.d/postgresql-custom.sh
    
    echo_success "环境变量配置完成"
}

# 启用 PostGIS 扩展
enable_postgis() {
    echo_info "正在配置 PostGIS 扩展..."
    
    sleep 5
    
    export PATH="${PREFIX_PG}/bin:$PATH"
    export LD_LIBRARY_PATH="${PREFIX_DEPS}/lib:${PREFIX_PG}/lib:$LD_LIBRARY_PATH"
    
    su - postgres -c "$PREFIX_PG/bin/psql -c 'CREATE EXTENSION IF NOT EXISTS postgis;'"
    su - postgres -c "$PREFIX_PG/bin/psql -c 'CREATE EXTENSION IF NOT EXISTS postgis_topology;'"
    
    POSTGIS_VERSION=$(su - postgres -c "$PREFIX_PG/bin/psql -t -c 'SELECT postgis_version();' 2>/dev/null")
    if [ -n "$POSTGIS_VERSION" ]; then
        echo_success "PostGIS 配置完成，版本: $POSTGIS_VERSION"
    else
        echo_error "PostGIS 配置失败，请检查是否正确安装"
    fi
}

# 配置防火墙
configure_firewall() {
    echo_info "正在配置防火墙..."
    
    if command -v firewall-cmd &> /dev/null && firewall-cmd --state &> /dev/null; then
        firewall-cmd --permanent --add-port=5432/tcp
        firewall-cmd --reload
        echo_success "防火墙配置完成"
    else
        echo_warning "firewalld 未运行，跳过防火墙配置"
    fi
}

# 设置 PostgreSQL 密码
set_postgres_password() {
    echo_info "正在设置 PostgreSQL 密码..."
    
    read -s -p "请输入 PostgreSQL 的 postgres 用户密码: " PGPASSWORD
    echo
    
    su - postgres -c "$PREFIX_PG/bin/psql -c \"ALTER USER postgres WITH PASSWORD '$PGPASSWORD';\""
    
    echo_success "PostgreSQL 密码设置完成"
}

# 清理临时文件
cleanup() {
    echo_info "正在清理临时文件..."
    
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
    echo_info "开始编译安装 PostgreSQL ${PG_VERSION} 和 PostGIS ${POSTGIS_VERSION} (Rocky Linux 9)..."
    
    check_root
    detect_os
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
