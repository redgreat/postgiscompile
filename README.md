# PostGISCompile

**项目概述**
- 面向 RHEL/CentOS/Rocky 8/9 的离线环境，提供 PostgreSQL/PostGIS 的编译安装与自动配置，以及一套无需 Grafana/Prometheus 的轻量监控与企业微信告警方案。

**核心能力**
- 离线安装：自动选择离线包目录、创建 `postgresql-custom` 服务、启用常用扩展与安全认证模板
- 监控告警：`monitor/` 目录提供 Python 监控脚本、配置模板、systemd 服务与定时器、日志轮转、专用 SQL、可选主机采集与单元测试

**目录速览**
- 安装脚本：`bin/install.sh`、`bin/rockylinux9_install.sh`
- 配置模板：`config/postgresql.conf.template`、`config/pg_hba.conf.template`
- 离线包：`packages/rhel8|rhel9/`
- 监控：`monitor/monitor_pg.py`、`monitor/config/config.json`、`monitor/systemd/*`、`monitor/logrotate/monitor_pg`、`monitor/sql/*`、`monitor/pg_collector.sh`、`monitor/tests/*`、`monitor/DEPLOY.md`

**快速开始**
- 离线安装：`sudo bash bin/install.sh`
- 监控部署：参见 `monitor/DEPLOY.md`，配置 `/etc/monitor/config.json`，执行 `systemctl enable --now monitor_pg` 与 `systemctl enable --now pg_collector.timer`

**注意事项**
- 建议监控账号授予 `pg_monitor` 并启用 TLS（`sslmode=require`）
- Windows 上 `pg_cron` 不支持后台工作进程，建议在 Linux 实例启用或使用替代方案
