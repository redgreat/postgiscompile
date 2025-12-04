# Rocky Linux 9 纯离线安装 - 快速开始

## 问题解决

你遇到的错误是因为脚本尝试使用 `dnf` 从网络源下载包，但在纯离线环境下无法访问网络。

## 已完成的修改

✅ **安装脚本已修改为纯离线模式**
- 移除了所有 `dnf install` 网络下载命令
- 改为检查系统是否已安装必需工具
- 只使用本地 RPM 包和源码包

## 使用步骤

### 1. 检查离线环境

在运行安装脚本前，先检查环境是否准备就绪：

```bash
cd /path/to/postgiscomplie
bash scripts/check_offline_environment.sh
```

### 2. 准备基础工具（如果检查失败）

如果检查脚本提示缺少基础工具，有两种方法：

#### 方法 A：使用 Rocky Linux 9 ISO（推荐）

```bash
# 挂载 ISO
mkdir -p /mnt/iso
mount -o loop /path/to/Rocky-9.x-x86_64-dvd.iso /mnt/iso

# 配置本地源
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

# 安装开发库（推荐）
dnf install -y openssl-devel readline-devel zlib-devel

# 完成后卸载 ISO
umount /mnt/iso
rm /etc/yum.repos.d/local.repo
```

#### 方法 B：使用下载脚本（推荐）

项目提供了一个专门的脚本来下载这些基础工具：

```bash
# 在有网络的机器上运行
bash scripts/download_base_tools.sh

# 这将下载 gcc, gcc-c++, make, tar, bzip2, xz 到 packages/rockylinux9/rpm_base/ 目录
# 然后将整个 packages 目录传输到离线环境
```

#### 方法 C：手动安装 RPM 包

如果你已经有 RPM 包：

```bash
# 安装基础工具（需要从 ISO 或镜像站获取这些包）
# 推荐使用 download_base_tools.sh 脚本下载
rpm -Uvh packages/rockylinux9/rpm_base/*.rpm
```

### 3. 运行安装脚本

```bash
cd /path/to/postgiscomplie
bash bin/rockylinux9_install.sh
```

## 脚本工作流程

修改后的脚本现在会：

1. ✅ 检查 root 权限
2. ✅ 检测操作系统版本
3. ✅ **检查基础工具**（gcc, g++, make, tar 等）
   - 如果缺少，会提示安装方法并退出
4. ✅ **检查系统开发库**（openssl-devel, readline-devel, zlib-devel）
   - 如果缺少，会显示警告但继续（这些是可选的）
5. ✅ 从本地 RPM 安装编译工具（m4, gettext, autoconf, automake, bison）
6. ✅ 从本地源码编译安装所有依赖和 PostgreSQL/PostGIS

## 最小化要求

### 必需的系统工具
- gcc
- g++ (gcc-c++)
- make
- tar
- bzip2
- xz

### 推荐的开发库
- openssl-devel
- readline-devel
- zlib-devel

### 必需的离线包

**源码包** (放在 `packages/rockylinux9/`):
- postgresql-18.1.tar.bz2
- postgis-3.6.0.tar.gz
- geos-3.14.0.tar.bz2
- proj-9.7.0.tar.gz
- json-c-0.18-20240915.tar.gz
- protobuf-c-1.5.2.tar.gz
- sqlite-autoconf-3460000.tar.gz
- cmake-3.31.3.tar.gz

**RPM 包** (放在 `packages/rockylinux9/rpm/`):
- m4-1.4.19-1.el9.x86_64.rpm
- gettext-0.22.5-2.el9.x86_64.rpm
- autoconf-2.71-3.el9.noarch.rpm
- automake-1.16.5-11.el9.noarch.rpm
- bison-3.7.4-5.el9.x86_64.rpm

## 常见问题

### Q: 脚本提示 "gcc 未安装" 怎么办？

**A:** 需要先安装 gcc。最简单的方法是使用 Rocky Linux 9 ISO 配置本地源，参考上面的"方法 A"。

### Q: 没有 ISO，如何获取基础工具的 RPM 包？

**A:** 在有网络的机器上下载：

```bash
# 在有网络的 Rocky Linux 9 机器上
dnf download --resolve gcc gcc-c++ make tar bzip2 xz

# 将下载的 RPM 包传输到离线环境
# 然后安装
rpm -Uvh *.rpm
```

### Q: 开发库是必需的吗？

**A:** 不是必需的，但强烈推荐：
- **openssl-devel**: 提供 SSL/TLS 加密连接支持
- **readline-devel**: 提供命令行编辑功能
- **zlib-devel**: 提供数据压缩支持

没有这些库，PostgreSQL 仍然可以编译和运行，但会缺少某些功能。

### Q: 如何验证环境是否准备好？

**A:** 运行检查脚本：

```bash
bash scripts/check_offline_environment.sh
```

如果所有检查通过（或只有警告），就可以运行安装脚本了。

## 相关文档

- **离线环境准备指南**: `docs/rockylinux9_offline_preparation.md`
- **RPM 包下载位置**: `docs/rockylinux9_rpm_download_locations.md`
- **快速参考**: `docs/rockylinux9_rpm_quick_reference.md`
- **包列表**: `packages/rockylinux9/packages_list.txt`

## 获取帮助

如果遇到问题：

1. 运行检查脚本查看具体缺少什么
2. 查看详细的离线准备文档
3. 检查安装脚本的错误输出

## 总结

现在的安装脚本已经完全支持纯离线环境，只需要：

1. ✅ 系统预装基础编译工具（gcc, g++, make 等）
2. ✅ 准备好所有源码包和 RPM 包
3. ✅ 运行安装脚本

不再需要网络连接！
