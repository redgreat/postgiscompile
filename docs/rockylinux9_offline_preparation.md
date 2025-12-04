# Rocky Linux 9 离线环境准备指南

## 概述

本文档说明如何在**纯离线环境**下准备 PostgreSQL 18 + PostGIS 3.6.0 的安装环境。

## 前提条件

在离线环境中运行安装脚本之前，需要确保系统已安装以下基础工具。

### 必需的系统工具

这些工具通常在 Rocky Linux 9 最小化安装中已包含，如果没有，需要从 ISO 或镜像站获取：

| 工具 | RPM 包名 | 说明 |
|------|----------|------|
| gcc | gcc-*.el9.x86_64.rpm | C 编译器 |
| g++ | gcc-c++-*.el9.x86_64.rpm | C++ 编译器 |
| make | make-*.el9.x86_64.rpm | 构建工具 |
| tar | tar-*.el9.x86_64.rpm | 解压工具 |
| bzip2 | bzip2-*.el9.x86_64.rpm | 压缩工具 |
| xz | xz-*.el9.x86_64.rpm | 压缩工具 |

### 推荐的系统开发库

这些库不是必需的，但强烈建议安装以获得完整功能：

| 库 | RPM 包名 | 说明 |
|------|----------|------|
| openssl-devel | openssl-devel-*.el9.x86_64.rpm | SSL/TLS 支持 |
| readline-devel | readline-devel-*.el9.x86_64.rpm | 命令行编辑支持 |
| zlib-devel | zlib-devel-*.el9.x86_64.rpm | 压缩库支持 |

## 离线环境准备步骤

### 步骤 1: 在有网络的 Rocky Linux 9 系统上准备

#### 1.1 安装基础工具（如果未安装）

```bash
# 安装基础编译工具
dnf install -y gcc gcc-c++ make tar bzip2 xz

# 安装系统开发库
dnf install -y openssl-devel readline-devel zlib-devel
```

#### 1.2 下载所有离线包

使用项目提供的下载脚本：

```bash
# 克隆或下载项目
cd /path/to/postgiscomplie

# 下载 RPM 包
bash scripts/download_rockylinux9_rpms.sh

# 下载源码包（如果还没有）
cd packages/rockylinux9

# PostgreSQL
wget https://ftp.postgresql.org/pub/source/v18.1/postgresql-18.1.tar.bz2

# PostGIS
wget https://download.osgeo.org/postgis/source/postgis-3.6.0.tar.gz

# GEOS
wget https://download.osgeo.org/geos/geos-3.14.0.tar.bz2

# PROJ
wget https://download.osgeo.org/proj/proj-9.7.0.tar.gz

# JSON-C
wget https://github.com/json-c/json-c/archive/refs/tags/json-c-0.18-20240915.tar.gz

# protobuf-c
wget https://github.com/protobuf-c/protobuf-c/releases/download/v1.5.2/protobuf-c-1.5.2.tar.gz

# SQLite
wget https://www.sqlite.org/2024/sqlite-autoconf-3460000.tar.gz

# CMake
wget https://github.com/Kitware/CMake/releases/download/v3.31.3/cmake-3.31.3.tar.gz
```

#### 1.3 打包整个项目

```bash
# 返回项目根目录
cd /path/to/postgiscomplie

# 打包整个项目
tar -czf postgiscomplie-offline.tar.gz .

# 或者只打包必要的文件
tar -czf postgiscomplie-offline.tar.gz \
    bin/ \
    packages/ \
    scripts/ \
    docs/ \
    config/
```

### 步骤 2: 传输到离线环境

将打包文件传输到离线环境：

```bash
# 使用 U 盘、移动硬盘或其他方式传输
# 在离线环境解压
tar -xzf postgiscomplie-offline.tar.gz -C /opt/
cd /opt/postgiscomplie
```

### 步骤 3: 在离线环境安装基础工具

#### 3.1 检查已安装的工具

```bash
# 检查 gcc
gcc --version

# 检查 g++
g++ --version

# 检查 make
make --version

# 检查 tar
tar --version
```

#### 3.2 如果缺少工具，从 ISO 安装

如果系统缺少基础工具，可以从 Rocky Linux 9 ISO 安装：

```bash
# 挂载 ISO
mkdir -p /mnt/iso
mount -o loop /path/to/Rocky-9.x-x86_64-dvd.iso /mnt/iso

# 配置本地 yum 源
cat > /etc/yum.repos.d/local.repo <<EOF
[local-baseos]
name=Rocky Linux 9 - BaseOS (Local)
baseurl=file:///mnt/iso/BaseOS
enabled=1
gpgcheck=0

[local-appstream]
name=Rocky Linux 9 - AppStream (Local)
baseurl=file:///mnt/iso/AppStream
enabled=1
gpgcheck=0
EOF

# 清理缓存
dnf clean all

# 安装基础工具
dnf install -y gcc gcc-c++ make tar bzip2 xz

# 安装开发库
dnf install -y openssl-devel readline-devel zlib-devel

# 安装完成后，卸载 ISO
umount /mnt/iso
rm /etc/yum.repos.d/local.repo
```

#### 3.3 或者手动安装 RPM 包

如果不想使用 ISO，可以手动安装 RPM 包：

```bash
# 从项目的 packages/rockylinux9/rpm/ 目录安装
cd /opt/postgiscomplie/packages/rockylinux9/rpm

# 安装所有 RPM 包
rpm -Uvh *.rpm --nodeps --force

# 或者单独安装
rpm -Uvh m4-1.4.19-1.el9.x86_64.rpm
rpm -Uvh gettext-0.22.5-2.el9.x86_64.rpm
rpm -Uvh autoconf-2.71-3.el9.noarch.rpm
rpm -Uvh automake-1.16.5-11.el9.noarch.rpm
rpm -Uvh bison-3.7.4-5.el9.x86_64.rpm
```

### 步骤 4: 运行安装脚本

```bash
cd /opt/postgiscomplie
bash bin/rockylinux9_install.sh
```

## 离线安装脚本的工作流程

修改后的安装脚本 (`rockylinux9_install.sh`) 现在支持纯离线模式：

### 1. 检查阶段
- ✅ 检查是否为 root 用户
- ✅ 检测操作系统版本
- ✅ **检查基础编译工具**（gcc, g++, make, tar）
- ✅ **检查系统开发库**（openssl-devel, readline-devel, zlib-devel）
- ⚠️ 如果缺少工具，脚本会提示安装方法并退出

### 2. 安装阶段
- ✅ 从本地 RPM 包安装编译工具（m4, gettext, autoconf, automake, bison）
- ✅ 从本地源码编译安装 CMake
- ✅ 从本地源码编译安装所有依赖库
- ✅ 从本地源码编译安装 PostgreSQL
- ✅ 从本地源码编译安装 PostGIS

### 3. 配置阶段
- ✅ 初始化数据库
- ✅ 配置 systemd 服务
- ✅ 启动服务
- ✅ 启用 PostGIS 扩展

## 常见问题

### Q1: 脚本提示 "gcc 未安装" 怎么办？

**A:** 需要先安装 gcc。有两种方法：

**方法 1（推荐）：使用 Rocky Linux 9 ISO**
```bash
# 挂载 ISO 并配置本地源，参考上面的步骤 3.2
```

**方法 2：手动下载 RPM 包**
```bash
# 在有网络的机器上下载
dnf download --resolve gcc gcc-c++ make tar bzip2 xz

# 传输到离线环境并安装
rpm -Uvh *.rpm
```

### Q2: 脚本提示缺少开发库怎么办？

**A:** 开发库不是必需的，但建议安装。脚本会显示警告但继续执行。

如果想安装开发库：
```bash
# 使用 ISO 安装
dnf install -y openssl-devel readline-devel zlib-devel

# 或手动下载 RPM 包
dnf download --resolve openssl-devel readline-devel zlib-devel
```

### Q3: 如何验证离线包是否完整？

**A:** 检查 `packages/rockylinux9/` 目录：

```bash
cd packages/rockylinux9
ls -lh

# 应该包含以下文件：
# - postgresql-18.1.tar.bz2
# - postgis-3.6.0.tar.gz
# - geos-3.14.0.tar.bz2
# - proj-9.7.0.tar.gz
# - json-c-0.18-20240915.tar.gz
# - protobuf-c-1.5.2.tar.gz
# - sqlite-autoconf-3460000.tar.gz
# - cmake-3.31.3.tar.gz

# RPM 包目录
ls -lh rpm/
# 应该包含：
# - m4-1.4.19-1.el9.x86_64.rpm
# - gettext-0.22.5-2.el9.x86_64.rpm
# - autoconf-2.71-3.el9.noarch.rpm
# - automake-1.16.5-11.el9.noarch.rpm
# - bison-3.7.4-5.el9.x86_64.rpm
```

### Q4: 编译过程中出现 "command not found" 错误？

**A:** 可能是缺少某个工具。检查错误信息中提到的命令，然后：

```bash
# 查找包含该命令的 RPM 包
dnf provides */命令名

# 或在有网络的机器上查询
yum whatprovides */命令名
```

### Q5: 如何在完全没有网络的环境下准备？

**A:** 使用 Rocky Linux 9 完整 DVD ISO：

1. 下载 Rocky Linux 9 DVD ISO（约 10GB）
2. 从 ISO 中提取所需的 RPM 包
3. 下载本项目的所有源码包
4. 打包传输到离线环境

## 最小化离线包清单

如果存储空间有限，以下是最小化的必需文件：

### 源码包（约 150MB）
```
postgresql-18.1.tar.bz2          (约 25MB)
postgis-3.6.0.tar.gz             (约 15MB)
geos-3.14.0.tar.bz2              (约 3MB)
proj-9.7.0.tar.gz                (约 8MB)
json-c-0.18-20240915.tar.gz      (约 500KB)
protobuf-c-1.5.2.tar.gz          (约 500KB)
sqlite-autoconf-3460000.tar.gz   (约 3MB)
cmake-3.31.3.tar.gz              (约 10MB)
```

### RPM 包（约 10MB）
```
m4-1.4.19-1.el9.x86_64.rpm
gettext-0.22.5-2.el9.x86_64.rpm
autoconf-2.71-3.el9.noarch.rpm
automake-1.16.5-11.el9.noarch.rpm
bison-3.7.4-5.el9.x86_64.rpm
```

### 脚本和配置（约 1MB）
```
bin/rockylinux9_install.sh
config/postgresql.conf.template
config/pg_hba.conf.template
```

**总计：约 160MB**

## 推荐的离线准备流程

```bash
# 1. 在有网络的 Rocky Linux 9 系统上
git clone https://github.com/your-repo/postgiscomplie.git
cd postgiscomplie

# 2. 运行下载脚本
bash scripts/download_rockylinux9_rpms.sh
bash scripts/download_all_sources.sh  # 如果有这个脚本

# 3. 验证文件完整性
bash scripts/verify_offline_packages.sh  # 如果有这个脚本

# 4. 打包
tar -czf postgiscomplie-offline-complete.tar.gz .

# 5. 传输到离线环境
# ... 使用 U 盘或其他方式 ...

# 6. 在离线环境解压并安装
tar -xzf postgiscomplie-offline-complete.tar.gz -C /opt/
cd /opt/postgiscomplie
bash bin/rockylinux9_install.sh
```

## 相关文档

- [RPM 包下载位置说明](./rockylinux9_rpm_download_locations.md)
- [RPM 包快速参考](./rockylinux9_rpm_quick_reference.md)
- [包列表](../packages/rockylinux9/packages_list.txt)
