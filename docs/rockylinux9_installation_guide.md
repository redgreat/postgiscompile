# PostgreSQL 18 + PostGIS 3.6.0 Rocky Linux 9 离线安装指南

## 概述
本文档提供在 Rocky Linux 9 系统上离线安装 PostgreSQL 18 和 PostGIS 3.6.0 的完整指南。
基于 SteamOS 9 的稳定系统架构，使用最新稳定版本组件。

## 版本信息
根据 [PostGIS 官方兼容性文档](https://trac.osgeo.org/postgis/wiki/UsersWikiPostgreSQLPostGIS)，本安装使用以下版本:

| 组件 | 版本 | 说明 |
|------|------|------|
| PostgreSQL | 18.1 | 最新稳定版 |
| PostGIS | 3.6.0 | 最新稳定版 |
| GEOS | 3.14.0 | 几何引擎 |
| PROJ | 9.7.0 | 坐标转换库 |
| protobuf-c | 1.5.2 | PostGIS 3.6 新增依赖 |
| json-c | 0.18 | JSON 支持 |
| SQLite | 3.46.0 | 数据库引擎 |
| CMake | 3.31.3 | 构建工具 |

## 系统要求

### 硬件要求
- CPU: 2核心或以上 (推荐4核心)
- 内存: 4GB 或以上 (推荐8GB)
- 磁盘: 至少15GB可用空间

### 软件要求
- 操作系统: Rocky Linux 9.x
- 用户权限: root
- 网络: 离线环境 (所有依赖包需提前下载)

## 安装前准备

### 1. 下载所有依赖包
将以下文件下载到 `packages/rockylinux9/` 目录:

#### 核心组件
```bash
postgresql-18.1.tar.bz2
postgis-3.6.0.tar.gz
```

#### 地理空间库
```bash
geos-3.14.0.tar.bz2
proj-9.7.0.tar.gz
```

#### 工具库
```bash
json-c-0.18-20240915.tar.gz
protobuf-c-1.5.2.tar.gz
sqlite-autoconf-3460000.tar.gz
cmake-3.31.3.tar.gz
```

#### RPM 系统工具包
```bash
m4-1.4.19-1.el9.x86_64.rpm
gettext-0.22.5-2.el9.x86_64.rpm
autoconf-2.71-3.el9.noarch.rpm
automake-1.16.5-11.el9.noarch.rpm
bison-3.7.4-5.el9.x86_64.rpm
```

### 2. 目录结构
确保目录结构如下:
```
postgresql_installer/
├── bin/
│   └── rockylinux9_install.sh    # 安装脚本
├── packages/
│   └── rockylinux9/              # Rocky Linux 9 依赖包
│       ├── postgresql-18.1.tar.bz2
│       ├── postgis-3.6.0.tar.gz
│       ├── geos-3.14.0.tar.bz2
│       ├── proj-9.7.0.tar.gz
│       ├── json-c-0.18-20240915.tar.gz
│       ├── protobuf-c-1.5.2.tar.gz
│       ├── sqlite-autoconf-3460000.tar.gz
│       ├── cmake-3.31.3.tar.gz
│       └── *.rpm (系统工具包)
└── config/
    ├── postgresql.conf.template   # 可选配置模板
    └── pg_hba.conf.template       # 可选认证模板
```

## 安装步骤

### 1. 上传安装包
将整个 `postgresql_installer` 目录上传到 Rocky Linux 9 服务器:
```bash
# 示例: 使用 scp 上传
scp -r postgresql_installer root@your-server:/opt/
```

### 2. 赋予执行权限
```bash
cd /opt/postgresql_installer/bin
chmod +x rockylinux9_install.sh
```

### 3. 执行安装
```bash
# 以 root 用户执行
./rockylinux9_install.sh
```

### 4. 安装过程
脚本将自动执行以下步骤:
1. ✓ 检查 root 权限
2. ✓ 检测操作系统 (确认为 Rocky Linux 9)
3. ✓ 安装基础编译工具 (gcc, make, etc.)
4. ✓ 启用 CRB 仓库 (CodeReady Builder)
5. ✓ 创建安装目录和 postgres 用户
6. ✓ 编译安装 CMake
7. ✓ 安装编译工具 (m4, autoconf, automake, bison)
8. ✓ 编译安装依赖库 (SQLite, JSON-C, PROJ, GEOS, protobuf-c)
9. ✓ 编译安装 PostgreSQL 18
10. ✓ 编译安装 PostGIS 3.6.0
11. ✓ 配置动态库加载路径
12. ✓ 初始化数据库
13. ✓ 配置 PostgreSQL
14. ✓ 创建 systemd 服务
15. ✓ 启动服务并设置自启动
16. ✓ 配置环境变量
17. ✓ 启用 PostGIS 扩展
18. ✓ 配置防火墙 (开放5432端口)
19. ✓ 设置 postgres 用户密码

## 安装后配置

### 1. 加载环境变量
```bash
# 重新登录，或执行:
source /etc/profile.d/postgresql-custom.sh
```

### 2. 验证安装
```bash
# 检查 PostgreSQL 版本
psql --version

# 连接数据库
psql -U postgres -h localhost

# 在 psql 中验证 PostGIS
SELECT postgis_version();
SELECT postgis_full_version();
```

### 3. 服务管理
```bash
# 启动服务
systemctl start postgresql-custom

# 停止服务
systemctl stop postgresql-custom

# 重启服务
systemctl restart postgresql-custom

# 查看状态
systemctl status postgresql-custom

# 查看日志
journalctl -u postgresql-custom -f
```

## 安装路径说明

| 路径 | 说明 |
|------|------|
| `/opt/postgresql/postgres-18` | PostgreSQL 主程序目录 |
| `/opt/postgresql/deps` | 依赖库安装目录 |
| `/opt/postgresql/data` | 数据库数据目录 |
| `/etc/ld.so.conf.d/postgresql-custom.conf` | 动态库配置 |
| `/etc/profile.d/postgresql-custom.sh` | 环境变量配置 |
| `/usr/lib/systemd/system/postgresql-custom.service` | systemd 服务文件 |

## 配置优化建议

### 1. PostgreSQL 性能调优
编辑 `/opt/postgresql/data/postgresql.conf`:

```ini
# 内存设置 (根据服务器配置调整)
shared_buffers = 2GB              # 系统内存的 25%
effective_cache_size = 6GB        # 系统内存的 50-75%
work_mem = 64MB                   # 复杂查询内存
maintenance_work_mem = 512MB      # 维护操作内存

# 连接设置
max_connections = 200             # 最大连接数

# WAL 设置
wal_buffers = 16MB
checkpoint_completion_target = 0.9

# 查询规划器
random_page_cost = 1.1            # SSD 存储建议值
effective_io_concurrency = 200    # SSD 并发 I/O
```

### 2. PostGIS 配置
```sql
-- 创建支持 PostGIS 的数据库
CREATE DATABASE gisdb;
\c gisdb

-- 启用 PostGIS 扩展
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_topology;

-- 验证安装
SELECT postgis_full_version();
```

### 3. 远程访问配置
编辑 `/opt/postgresql/data/pg_hba.conf`:
```
# 允许指定网段访问
host    all             all             192.168.1.0/24          scram-sha-256

# 允许所有 IP 访问 (不推荐生产环境)
host    all             all             0.0.0.0/0               scram-sha-256
```

重启服务使配置生效:
```bash
systemctl restart postgresql-custom
```

## 特性说明

### 1. 完全离线安装
- 所有依赖包从本地 packages 目录获取
- 不需要互联网连接
- 适合内网或隔离环境部署

### 2. 依赖隔离
- 所有依赖库安装到 `/opt/postgresql/deps`
- 不影响系统已有的库版本
- 避免版本冲突

### 3. RPM 优先策略
- 系统工具优先使用 RPM 包安装
- 减少编译时间
- 提高安装稳定性

### 4. 最新稳定版本
- 使用 PostgreSQL 18 最新特性
- PostGIS 3.6.0 支持最新地理空间功能
- 所有依赖库使用官方推荐版本

## 常见问题

### 1. 编译失败
**问题**: CMake 或其他组件编译失败
**解决**: 
- 检查是否有足够的磁盘空间
- 确认所有依赖包完整下载
- 查看错误日志定位具体问题

### 2. 服务启动失败
**问题**: PostgreSQL 服务无法启动
**解决**:
```bash
# 查看详细日志
journalctl -u postgresql-custom -n 50

# 检查数据目录权限
ls -la /opt/postgresql/data

# 手动启动测试
su - postgres
/opt/postgresql/postgres-18/bin/pg_ctl start -D /opt/postgresql/data
```

### 3. PostGIS 扩展创建失败
**问题**: CREATE EXTENSION postgis 失败
**解决**:
```bash
# 检查动态库路径
ldd /opt/postgresql/postgres-18/lib/postgresql/postgis-3.so

# 确认环境变量
echo $LD_LIBRARY_PATH

# 重新配置 ldconfig
ldconfig
```

### 4. 远程连接被拒绝
**问题**: 无法从远程主机连接
**解决**:
- 检查防火墙: `firewall-cmd --list-ports`
- 检查 pg_hba.conf 配置
- 检查 postgresql.conf 中的 listen_addresses

## 卸载步骤

如需完全卸载:
```bash
# 1. 停止并禁用服务
systemctl stop postgresql-custom
systemctl disable postgresql-custom

# 2. 删除服务文件
rm -f /usr/lib/systemd/system/postgresql-custom.service
systemctl daemon-reload

# 3. 删除环境变量配置
rm -f /etc/profile.d/postgresql-custom.sh

# 4. 删除动态库配置
rm -f /etc/ld.so.conf.d/postgresql-custom.conf
ldconfig

# 5. 删除安装目录
rm -rf /opt/postgresql

# 6. 删除 postgres 用户 (可选)
userdel -r postgres
```

## 备份与恢复

### 备份数据库
```bash
# 备份单个数据库
/opt/postgresql/postgres-18/bin/pg_dump -U postgres -d gisdb > gisdb_backup.sql

# 备份所有数据库
/opt/postgresql/postgres-18/bin/pg_dumpall -U postgres > all_databases_backup.sql

# 备份数据目录 (需先停止服务)
systemctl stop postgresql-custom
tar -czf postgresql_data_backup.tar.gz /opt/postgresql/data
systemctl start postgresql-custom
```

### 恢复数据库
```bash
# 恢复单个数据库
/opt/postgresql/postgres-18/bin/psql -U postgres -d gisdb < gisdb_backup.sql

# 恢复所有数据库
/opt/postgresql/postgres-18/bin/psql -U postgres < all_databases_backup.sql
```

## 版本升级

### 小版本升级 (如 18.1 -> 18.2)
```bash
# 1. 备份数据
# 2. 下载新版本源码
# 3. 重新编译安装到相同目录
# 4. 重启服务
```

### 大版本升级 (如 18 -> 19)
```bash
# 需要使用 pg_upgrade 工具
# 详细步骤请参考 PostgreSQL 官方文档
```

## 参考资料

- [PostgreSQL 官方文档](https://www.postgresql.org/docs/18/)
- [PostGIS 官方文档](https://postgis.net/documentation/)
- [PostGIS 版本兼容性](https://trac.osgeo.org/postgis/wiki/UsersWikiPostgreSQLPostGIS)
- [PostGIS 包管理](https://trac.osgeo.org/postgis/wiki/UsersWikiPackages)
- [Rocky Linux 官方文档](https://docs.rockylinux.org/)

## 技术支持

如遇到问题，请检查:
1. 安装日志输出
2. PostgreSQL 日志: `/opt/postgresql/data/log/`
3. 系统日志: `journalctl -u postgresql-custom`

## 更新日志

- 2025-12-02: 初始版本
  * PostgreSQL 18.1
  * PostGIS 3.6.0
  * 支持 Rocky Linux 9
  * 完全离线安装
  * RPM 优先策略
