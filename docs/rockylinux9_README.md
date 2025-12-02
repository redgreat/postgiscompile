# Rocky Linux 9 PostgreSQL + PostGIS 离线安装

## 快速开始

### 版本信息
- **PostgreSQL**: 18.1
- **PostGIS**: 3.6.0
- **系统**: Rocky Linux 9 (基于 SteamOS 9)
- **安装方式**: 完全离线，源码编译

### 一键安装
```bash
cd bin
chmod +x rockylinux9_install.sh
./rockylinux9_install.sh
```

## 主要特性

✅ **最新稳定版本** - 使用 PostgreSQL 18 和 PostGIS 3.6.0  
✅ **完全离线安装** - 无需互联网连接  
✅ **RPM 优先策略** - 系统工具优先使用 RPM 包  
✅ **依赖隔离** - 不影响系统已有库版本  
✅ **自动化部署** - 一键完成所有配置  

## 必需文件

### 核心组件
- postgresql-18.1.tar.bz2
- postgis-3.6.0.tar.gz

### 依赖库
- geos-3.14.0.tar.bz2
- proj-9.7.0.tar.gz
- protobuf-c-1.5.2.tar.gz
- json-c-0.18-20240915.tar.gz
- sqlite-autoconf-3460000.tar.gz
- cmake-3.31.3.tar.gz

### RPM 工具包
- m4-1.4.19-1.el9.x86_64.rpm
- gettext-0.22.5-2.el9.x86_64.rpm
- autoconf-2.71-3.el9.noarch.rpm
- automake-1.16.5-11.el9.noarch.rpm
- bison-3.7.4-5.el9.x86_64.rpm

**所有文件放置在**: `packages/rockylinux9/`

## 详细文档

📖 [完整安装指南](../docs/rockylinux9_installation_guide.md)  
📦 [依赖包列表](../packages/rockylinux9/packages_list.txt)  

## 版本兼容性

根据 [PostGIS 官方文档](https://trac.osgeo.org/postgis/wiki/UsersWikiPostgreSQLPostGIS):

| PostgreSQL | PostGIS | GEOS | PROJ |
|------------|---------|------|------|
| 18.x | 3.6.0 | 3.14.0 | 9.7.0 |

## 安装后验证

```bash
# 检查版本
psql --version

# 连接数据库
psql -U postgres -h localhost

# 验证 PostGIS
SELECT postgis_version();
```

## 服务管理

```bash
systemctl start postgresql-custom    # 启动
systemctl stop postgresql-custom     # 停止
systemctl restart postgresql-custom  # 重启
systemctl status postgresql-custom   # 状态
```

## 安装位置

- **程序目录**: `/opt/postgresql/postgres-18`
- **数据目录**: `/opt/postgresql/data`
- **依赖目录**: `/opt/postgresql/deps`

## 注意事项

⚠️ 需要 root 权限  
⚠️ 至少 15GB 磁盘空间  
⚠️ 推荐 4GB+ 内存  
⚠️ 确保所有依赖包已下载  

## 参考链接

- [PostGIS 版本兼容性](https://trac.osgeo.org/postgis/wiki/UsersWikiPostgreSQLPostGIS)
- [PostGIS 包管理](https://trac.osgeo.org/postgis/wiki/UsersWikiPackages)
