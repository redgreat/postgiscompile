#!/bin/bash

# pgBackRest 备份脚本
# 用于执行 PostgreSQL 数据库备份

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
STANZA="main"
LOG_FILE="/var/log/pgbackrest/backup-script.log"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 检查 pgbackrest 是否安装
check_pgbackrest() {
    if ! command -v pgbackrest > /dev/null 2>&1; then
        log_error "pgbackrest 未安装"
        exit 1
    fi
    log_success "pgbackrest 已安装"
}

# 检查 PostgreSQL 状态
check_postgresql() {
    if ! systemctl is-active --quiet postgresql-custom; then
        log_error "PostgreSQL 服务未运行"
        exit 1
    fi
    log_success "PostgreSQL 服务正在运行"
}

# 执行备份
do_backup() {
    local backup_type=${1:-incr}
    
    log_info "开始执行 ${backup_type} 备份..."
    
    if pgbackrest --stanza="$STANZA" --type="$backup_type" backup; then
        log_success "${backup_type} 备份完成"
    else
        log_error "${backup_type} 备份失败"
        exit 1
    fi
}

# 显示备份信息
show_info() {
    log_info "当前备份信息:"
    pgbackrest --stanza="$STANZA" info
}

# 清理过期备份
expire_backups() {
    log_info "清理过期备份..."
    
    if pgbackrest --stanza="$STANZA" expire; then
        log_success "过期备份清理完成"
    else
        log_warning "过期备份清理失败"
    fi
}

# 显示使用说明
usage() {
    cat << EOF
用法: $0 [选项]

选项:
    full        执行完整备份
    incr        执行增量备份 (默认)
    diff        执行差异备份
    info        显示备份信息
    expire      清理过期备份
    help        显示此帮助信息

示例:
    $0 full     # 执行完整备份
    $0 incr     # 执行增量备份
    $0 info     # 查看备份信息

EOF
}

# 主函数
main() {
    local action=${1:-incr}
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case "$action" in
        full|incr|diff)
            check_pgbackrest
            check_postgresql
            do_backup "$action"
            show_info
            ;;
        info)
            check_pgbackrest
            show_info
            ;;
        expire)
            check_pgbackrest
            expire_backups
            show_info
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "未知选项: $action"
            usage
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
