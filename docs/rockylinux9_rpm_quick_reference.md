# Rocky Linux 9 RPM 包下载快速参考

## 包下载地址速查表

| 包名 | 架构 | 仓库 | 完整下载地址 |
|------|------|------|--------------|
| m4-1.4.19-1.el9 | x86_64 | AppStream | https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/m/m4-1.4.19-1.el9.x86_64.rpm |
| gettext-0.22.5-2.el9 | x86_64 | BaseOS | https://dl.rockylinux.org/vault/rocky/9.6/BaseOS/x86_64/os/Packages/g/gettext-0.22.5-2.el9.x86_64.rpm |
| autoconf-2.71-3.el9 | noarch | AppStream | https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/a/autoconf-2.71-3.el9.noarch.rpm |
| automake-1.16.5-11.el9 | noarch | AppStream | https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/a/automake-1.16.5-11.el9.noarch.rpm |
| bison-3.7.4-5.el9 | x86_64 | AppStream | https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/b/bison-3.7.4-5.el9.x86_64.rpm |

## 仓库目录结构

```
https://dl.rockylinux.org/vault/rocky/9.6/
├── BaseOS/x86_64/os/Packages/          # 基础系统包
│   ├── a/
│   ├── b/
│   ├── ...
│   └── z/
├── AppStream/x86_64/os/Packages/       # 应用程序流
│   ├── a/
│   ├── b/
│   ├── ...
│   └── z/
└── CRB/x86_64/os/Packages/             # 开发工具 (CodeReady Builder)
    ├── a/
    ├── b/
    ├── ...
    └── z/
```

## 一键下载命令

### 使用 wget 下载所有包

```bash
# 创建下载目录
mkdir -p packages/rockylinux9/rpm
cd packages/rockylinux9/rpm

# 下载所有必需的包
wget https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/m/m4-1.4.19-1.el9.x86_64.rpm
wget https://dl.rockylinux.org/vault/rocky/9.6/BaseOS/x86_64/os/Packages/g/gettext-0.22.5-2.el9.x86_64.rpm
wget https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/a/autoconf-2.71-3.el9.noarch.rpm
wget https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/a/automake-1.16.5-11.el9.noarch.rpm
wget https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/b/bison-3.7.4-5.el9.x86_64.rpm
```

### 使用 curl 下载所有包

```bash
# 创建下载目录
mkdir -p packages/rockylinux9/rpm
cd packages/rockylinux9/rpm

# 下载所有必需的包
curl -O https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/m/m4-1.4.19-1.el9.x86_64.rpm
curl -O https://dl.rockylinux.org/vault/rocky/9.6/BaseOS/x86_64/os/Packages/g/gettext-0.22.5-2.el9.x86_64.rpm
curl -O https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/a/autoconf-2.71-3.el9.noarch.rpm
curl -O https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/a/automake-1.16.5-11.el9.noarch.rpm
curl -O https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/b/bison-3.7.4-5.el9.x86_64.rpm
```

## 可选开发包

这些包的版本号可能会随系统更新而变化，建议浏览目录查找最新版本：

| 包名 | 可能位置 |
|------|----------|
| libxml2-devel | https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/l/ |
| libxml2-devel | https://dl.rockylinux.org/vault/rocky/9.6/CRB/x86_64/os/Packages/l/ |
| libxslt-devel | https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/l/ |
| libxslt-devel | https://dl.rockylinux.org/vault/rocky/9.6/CRB/x86_64/os/Packages/l/ |

### 查找开发包的具体版本

```bash
# 使用 curl 列出 libxml2-devel 的所有版本
curl -s https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/l/ | \
  grep -o 'href="libxml2-devel[^"]*\.rpm"' | \
  sed 's/href="//;s/"//'

# 使用 curl 列出 libxslt-devel 的所有版本
curl -s https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/l/ | \
  grep -o 'href="libxslt-devel[^"]*\.rpm"' | \
  sed 's/href="//;s/"//'
```

## 使用自动化脚本

项目提供了自动下载脚本：

```bash
# 运行下载脚本
bash scripts/download_rockylinux9_rpms.sh
```

该脚本会：
1. 自动创建下载目录
2. 下载所有必需的 RPM 包
3. 显示下载进度和结果
4. 跳过已存在的文件
5. 提供失败包的重试建议

## 验证和安装

### 验证下载的包

```bash
# 检查 RPM 包签名
rpm -K *.rpm

# 查看包信息
rpm -qip m4-1.4.19-1.el9.x86_64.rpm

# 查看包依赖
rpm -qpR m4-1.4.19-1.el9.x86_64.rpm

# 列出包内文件
rpm -qpl m4-1.4.19-1.el9.x86_64.rpm
```

### 离线安装

```bash
# 方法 1: 使用 rpm 安装
rpm -ivh *.rpm

# 方法 2: 使用 dnf 本地安装（推荐，会自动解决依赖）
dnf localinstall *.rpm

# 方法 3: 安装单个包
rpm -ivh m4-1.4.19-1.el9.x86_64.rpm
```

## 镜像站替代地址

如果官方镜像站速度慢，可以使用以下国内镜像：

### 阿里云镜像
```
https://mirrors.aliyun.com/rockylinux/9.6/
```

### 清华大学镜像
```
https://mirrors.tuna.tsinghua.edu.cn/rocky/9.6/
```

### 中科大镜像
```
https://mirrors.ustc.edu.cn/rocky/9.6/
```

使用方法：将 `https://dl.rockylinux.org/vault/rocky/9.6/` 替换为上述镜像地址即可。

例如：
```bash
# 使用阿里云镜像下载 m4
wget https://mirrors.aliyun.com/rockylinux/9.6/AppStream/x86_64/os/Packages/m/m4-1.4.19-1.el9.x86_64.rpm
```

## 注意事项

1. **版本号可能变化**：包的小版本号可能随系统更新而变化
2. **架构选择**：确保下载 `x86_64` 或 `noarch` 架构的包
3. **依赖关系**：某些包可能有依赖，建议使用 `repotrack` 或 `dnf download --resolve`
4. **网络问题**：如果下载失败，尝试使用国内镜像站
5. **磁盘空间**：确保有足够的磁盘空间（约 50-100 MB）

## 相关文档

- 详细说明：[rockylinux9_rpm_download_locations.md](./rockylinux9_rpm_download_locations.md)
- 包列表：[../packages/rockylinux9/packages_list.txt](../packages/rockylinux9/packages_list.txt)
- 下载脚本：[../scripts/download_rockylinux9_rpms.sh](../scripts/download_rockylinux9_rpms.sh)
