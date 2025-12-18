#!/bin/bash

# PostgreSQL Exporter 安装配置脚本
# 用于 Prometheus + Grafana 监控平台
# 支持离线安装

set -e

# ==================== 配置参数 (请根据实际情况修改) ==================== #

# Prometheus 服务器地址 (用于配置说明,不影响 exporter 运行)
PROMETHEUS_SERVER="http://192.168.1.100:9090"

# Postgres Exporter 配置
EXPORTER_VERSION="0.18.1"                    # postgres_exporter 版本
EXPORTER_PACKAGE="postgres_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz"  # 离线包文件名
EXPORTER_PORT="9187"                         # exporter 监听端口
EXPORTER_USER="postgres_exporter"            # 运行 exporter 的系统用户

# PostgreSQL 连接配置
PG_HOST="localhost"                          # PostgreSQL 主机
PG_PORT="5432"                               # PostgreSQL 端口
PG_DATABASE="postgres"                       # 监控数据库
PG_MONITOR_USER="postgres_exporter"          # PostgreSQL 监控用户
PG_MONITOR_PASSWORD="ExporterPass2024"       # PostgreSQL 监控用户密码

# 安装路径
INSTALL_DIR="/opt/postgres_exporter"         # exporter 安装目录
CONFIG_DIR="/etc/postgres_exporter"          # 配置文件目录
LOG_DIR="/var/log/postgres_exporter"         # 日志目录

# 离线包路径
INSTALLER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOWNLOAD_DIR="${INSTALLER_DIR}/packages"

# ==================== 以下为脚本逻辑,一般不需要修改 ==================== #

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

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo_error "请以 root 用户运行此脚本"
        exit 1
    fi
    echo_success "用户权限检查通过"
}

# 检测操作系统
detect_os() {
    echo_info "正在检测操作系统..."
    
    if [ -f /etc/os-release ]; then
        OS_TYPE=$(grep -oP '^NAME="\K[^"]+' /etc/os-release)
        OS_VERSION=$(grep -oP '^VERSION_ID="\K[^"]+' /etc/os-release)
        MAJOR_VERSION=$(echo "$OS_VERSION" | awk -F'.' '{print $1}')
    else
        echo_error "无法识别操作系统类型"
        exit 1
    fi
    
    echo_success "操作系统: $OS_TYPE $OS_VERSION"
}

# 创建系统用户
create_exporter_user() {
    echo_info "正在创建 exporter 用户..."
    
    if ! id "$EXPORTER_USER" &> /dev/null; then
        useradd -r -s /bin/false "$EXPORTER_USER"
        echo_success "用户 $EXPORTER_USER 创建成功"
    else
        echo_warning "用户 $EXPORTER_USER 已存在"
    fi
}

# 创建目录
create_directories() {
    echo_info "正在创建安装目录..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    
    chown -R "$EXPORTER_USER":"$EXPORTER_USER" "$INSTALL_DIR"
    chown -R "$EXPORTER_USER":"$EXPORTER_USER" "$CONFIG_DIR"
    chown -R "$EXPORTER_USER":"$EXPORTER_USER" "$LOG_DIR"
    
    echo_success "目录创建完成"
}

# 安装 postgres_exporter
install_postgres_exporter() {
    echo_info "正在安装 postgres_exporter..."
    
    # 离线包路径
    local package="${DOWNLOAD_DIR}/srctar/${EXPORTER_PACKAGE}"
    
    # 检查离线包是否存在
    if [ ! -f "$package" ]; then
        echo_error "未找到离线包: $package"
        echo_info "请下载 postgres_exporter 到: ${DOWNLOAD_DIR}/srctar/"
        echo_info "文件名: ${EXPORTER_PACKAGE}"
        echo_info "下载地址: https://github.com/prometheus-community/postgres_exporter/releases/download/v${EXPORTER_VERSION}/${EXPORTER_PACKAGE}"
        exit 1
    fi
    
    # 解压到临时目录
    local temp_dir="/tmp/postgres_exporter_install"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    tar -xzf "$package" -C "$temp_dir" --strip-components=1
    
    # 复制二进制文件
    if [ -f "$temp_dir/postgres_exporter" ]; then
        cp "$temp_dir/postgres_exporter" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/postgres_exporter"
        chown "$EXPORTER_USER":"$EXPORTER_USER" "$INSTALL_DIR/postgres_exporter"
    else
        echo_error "未找到 postgres_exporter 二进制文件"
        exit 1
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    echo_success "postgres_exporter 安装完成"
}

# 创建 PostgreSQL 监控用户
create_pg_monitor_user() {
    echo_info "正在创建 PostgreSQL 监控用户..."
    
    # 检查 PostgreSQL 是否运行
    if ! systemctl is-active --quiet postgresql-custom; then
        echo_warning "PostgreSQL 服务未运行,跳过监控用户创建"
        echo_warning "请在 PostgreSQL 启动后手动执行:"
        echo_warning "  su - postgres -c \"PGHOST=/var/run/postgresql /opt/postgresql/postgres/bin/psql --no-password -c \\\"CREATE USER $PG_MONITOR_USER WITH PASSWORD '$PG_MONITOR_PASSWORD';\\\"\""
        echo_warning "  su - postgres -c \"PGHOST=/var/run/postgresql /opt/postgresql/postgres/bin/psql --no-password -c \\\"GRANT pg_monitor TO $PG_MONITOR_USER;\\\"\""
        return 0
    fi
    
    # 查找 psql 路径
    local PSQL_BIN=""
    if [ -f "/opt/postgresql/postgres/bin/psql" ]; then
        PSQL_BIN="/opt/postgresql/postgres/bin/psql"
    elif command -v psql > /dev/null 2>&1; then
        PSQL_BIN=$(command -v psql)
    else
        echo_error "未找到 psql 命令"
        echo_warning "请手动创建监控用户"
        return 0
    fi
    
    # 创建监控用户
    su - postgres -c "PGHOST=/var/run/postgresql $PSQL_BIN --no-password -c \"CREATE USER $PG_MONITOR_USER WITH PASSWORD '$PG_MONITOR_PASSWORD';\"" 2>/dev/null || \
        echo_warning "用户 $PG_MONITOR_USER 可能已存在"
    
    # 授予监控权限
    su - postgres -c "PGHOST=/var/run/postgresql $PSQL_BIN --no-password -c \"GRANT pg_monitor TO $PG_MONITOR_USER;\"" || true
    su - postgres -c "PGHOST=/var/run/postgresql $PSQL_BIN --no-password -c \"GRANT CONNECT ON DATABASE $PG_DATABASE TO $PG_MONITOR_USER;\"" || true
    
    echo_success "PostgreSQL 监控用户创建完成"
}

# 创建配置文件
create_config_files() {
    echo_info "正在创建配置文件..."
    
    # 创建环境变量文件
    cat > "$CONFIG_DIR/postgres_exporter.env" <<EOF
# PostgreSQL 连接配置
DATA_SOURCE_NAME=postgresql://$PG_MONITOR_USER:$PG_MONITOR_PASSWORD@$PG_HOST:$PG_PORT/$PG_DATABASE?sslmode=disable
EOF
    
    chmod 600 "$CONFIG_DIR/postgres_exporter.env"
    chown "$EXPORTER_USER":"$EXPORTER_USER" "$CONFIG_DIR/postgres_exporter.env"
    
    # 复制主配置文件模板
    TEMPLATE_DIR="${INSTALLER_DIR}/config"
    if [ -f "$TEMPLATE_DIR/postgres_exporter.yml.template" ]; then
        cp "$TEMPLATE_DIR/postgres_exporter.yml.template" "$CONFIG_DIR/postgres_exporter.yml"
    else
        # 创建空的主配置文件
        cat > "$CONFIG_DIR/postgres_exporter.yml" <<'EOF'
# postgres_exporter 主配置文件
{}
EOF
    fi
    chmod 644 "$CONFIG_DIR/postgres_exporter.yml"
    chown "$EXPORTER_USER":"$EXPORTER_USER" "$CONFIG_DIR/postgres_exporter.yml"
    
    # 复制查询配置文件模板
    if [ -f "$TEMPLATE_DIR/queries.yaml.template" ]; then
        cp "$TEMPLATE_DIR/queries.yaml.template" "$CONFIG_DIR/queries.yaml"
        chmod 644 "$CONFIG_DIR/queries.yaml"
        chown "$EXPORTER_USER":"$EXPORTER_USER" "$CONFIG_DIR/queries.yaml"
        echo_success "queries.yaml 配置文件已复制"
    else
        echo_warning "未找到 queries.yaml.template 模板文件,跳过"
        touch "$CONFIG_DIR/queries.yaml"
        chmod 644 "$CONFIG_DIR/queries.yaml"
        chown "$EXPORTER_USER":"$EXPORTER_USER" "$CONFIG_DIR/queries.yaml"
    fi
    
    echo_success "配置文件创建完成"
}

# 创建 systemd 服务
create_systemd_service() {
    echo_info "正在创建 systemd 服务..."
    
    cat > /etc/systemd/system/postgres_exporter.service <<EOF
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network.target postgresql-custom.service
Wants=postgresql-custom.service

[Service]
Type=simple
User=postgres_exporter
Group=postgres_exporter
EnvironmentFile=/etc/postgres_exporter/postgres_exporter.env
ExecStart=/opt/postgres_exporter/postgres_exporter \\
    --web.listen-address=:9187 \\
    --web.telemetry-path=/metrics \\
    --config.file=/etc/postgres_exporter/postgres_exporter.yml \\
    --extend.query-path=/etc/postgres_exporter/queries.yaml \\
    --log.level=info
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s

# 安全加固
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/postgres_exporter

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    
    echo_success "systemd 服务创建完成"
}

# 配置防火墙
configure_firewall() {
    echo_info "正在配置防火墙..."
    
    if command -v firewall-cmd &> /dev/null && firewall-cmd --state &> /dev/null; then
        firewall-cmd --permanent --add-port="$EXPORTER_PORT/tcp"
        firewall-cmd --reload
        echo_success "防火墙配置完成"
    else
        echo_warning "firewalld 未运行,跳过防火墙配置"
    fi
}

# 启动服务
start_service() {
    echo_info "正在启动 postgres_exporter 服务..."
    
    systemctl enable postgres_exporter
    systemctl start postgres_exporter
    
    sleep 2
    
    if systemctl is-active --quiet postgres_exporter; then
        echo_success "postgres_exporter 服务启动成功"
    else
        echo_error "postgres_exporter 服务启动失败"
        echo_info "查看日志: journalctl -u postgres_exporter -n 50"
        exit 1
    fi
}

# 验证安装
verify_installation() {
    echo_info "正在验证安装..."
    
    # 检查端口监听
    if ss -tuln | grep -q ":$EXPORTER_PORT"; then
        echo_success "Exporter 正在监听端口 $EXPORTER_PORT"
    else
        echo_warning "端口 $EXPORTER_PORT 未监听"
    fi
    
    # 测试 metrics 接口
    if command -v curl &> /dev/null; then
        if curl -s "http://localhost:$EXPORTER_PORT/metrics" | grep -q "pg_up"; then
            echo_success "Metrics 接口测试通过"
        else
            echo_warning "Metrics 接口测试失败"
        fi
    fi
}

# 显示安装信息
display_info() {
    echo_success "\n======================================="
    echo_success "PostgreSQL Exporter 安装完成!"
    echo_success "======================================="
    echo_info "安装目录: $INSTALL_DIR"
    echo_info "配置目录: $CONFIG_DIR"
    echo_info "日志目录: $LOG_DIR"
    echo_info "监听端口: $EXPORTER_PORT"
    echo_info ""
    echo_info "Metrics 地址: http://$(hostname -I | awk '{print $1}'):$EXPORTER_PORT/metrics"
    echo_info ""
    echo_info "服务管理:"
    echo_info "  启动: systemctl start postgres_exporter"
    echo_info "  停止: systemctl stop postgres_exporter"
    echo_info "  重启: systemctl restart postgres_exporter"
    echo_info "  状态: systemctl status postgres_exporter"
    echo_info "  日志: journalctl -u postgres_exporter -f"
    echo_info ""
    echo_info "Prometheus 配置:"
    echo_info "  在 Prometheus 服务器的 prometheus.yml 中添加:"
    echo_info ""
    echo_info "  scrape_configs:"
    echo_info "    - job_name: 'postgresql'"
    echo_info "      static_configs:"
    echo_info "        - targets: ['$(hostname -I | awk '{print $1}'):$EXPORTER_PORT']"
    echo_info "          labels:"
    echo_info "            instance: '$(hostname)'"
    echo_info ""
    echo_info "Grafana Dashboard:"
    echo_info "  推荐使用 Dashboard ID: 9628 (PostgreSQL Database)"
    echo_info "  导入地址: https://grafana.com/grafana/dashboards/9628"
    echo_info ""
    echo_warning "注意: 请确保 Prometheus 服务器可以访问此主机的 $EXPORTER_PORT 端口"
    echo_success "======================================="
}

# 主函数
main() {
    echo_info "开始安装 PostgreSQL Exporter..."
    
    check_root
    detect_os
    create_exporter_user
    create_directories
    install_postgres_exporter
    create_pg_monitor_user
    create_config_files
    create_systemd_service
    configure_firewall
    start_service
    verify_installation
    display_info
}

# 执行主函数
main
