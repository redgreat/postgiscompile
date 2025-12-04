# Rocky Linux 9 RPM 包下载位置说明

## 概述
本文档说明 `packages_list.txt` 中列出的 RPM 包在 Rocky Linux 9.6 镜像站的具体下载位置。

## 镜像站基础地址
```
https://dl.rockylinux.org/vault/rocky/9.6/
```

## Rocky Linux 9 仓库结构

Rocky Linux 9 有三个主要仓库：

1. **BaseOS** - 基础操作系统包
   - 路径：`BaseOS/x86_64/os/Packages/`
   - 说明：核心系统运行所需的基础包

2. **AppStream** - 应用程序流
   - 路径：`AppStream/x86_64/os/Packages/`
   - 说明：应用程序、开发工具、运行时环境等

3. **CRB (CodeReady Builder)** - 开发者工具
   - 路径：`CRB/x86_64/os/Packages/`
   - 说明：开发库、头文件等开发依赖

## 包下载位置详细说明

### 1. m4-1.4.19-1.el9.x86_64.rpm
- **仓库**：AppStream
- **完整路径**：
  ```
  https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/m/m4-1.4.19-1.el9.x86_64.rpm
  ```
- **说明**：M4 宏处理器，用于 autoconf

### 2. gettext-0.22.5-2.el9.x86_64.rpm
- **仓库**：BaseOS 或 AppStream
- **可能路径**：
  ```
  https://dl.rockylinux.org/vault/rocky/9.6/BaseOS/x86_64/os/Packages/g/gettext-0.22.5-2.el9.x86_64.rpm
  ```
  或
  ```
  https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/g/gettext-0.22.5-2.el9.x86_64.rpm
  ```
- **说明**：GNU 国际化工具

### 3. autoconf-2.71-3.el9.noarch.rpm
- **仓库**：AppStream
- **完整路径**：
  ```
  https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/a/autoconf-2.71-3.el9.noarch.rpm
  ```
- **说明**：自动配置工具

### 4. automake-1.16.5-11.el9.noarch.rpm
- **仓库**：AppStream
- **完整路径**：
  ```
  https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/a/automake-1.16.5-11.el9.noarch.rpm
  ```
- **说明**：自动化构建工具

### 5. bison-3.7.4-5.el9.x86_64.rpm
- **仓库**：AppStream
- **完整路径**：
  ```
  https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/b/bison-3.7.4-5.el9.x86_64.rpm
  ```
- **说明**：语法分析器生成器

### 6. libxml2-devel
- **仓库**：AppStream 或 CRB
- **可能路径**：
  ```
  https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/l/libxml2-devel-*.el9.x86_64.rpm
  ```
  或
  ```
  https://dl.rockylinux.org/vault/rocky/9.6/CRB/x86_64/os/Packages/l/libxml2-devel-*.el9.x86_64.rpm
  ```
- **说明**：XML 支持开发库

### 7. libxslt-devel
- **仓库**：AppStream 或 CRB
- **可能路径**：
  ```
  https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/l/libxslt-devel-*.el9.x86_64.rpm
  ```
  或
  ```
  https://dl.rockylinux.org/vault/rocky/9.6/CRB/x86_64/os/Packages/l/libxslt-devel-*.el9.x86_64.rpm
  ```
- **说明**：XSLT 支持开发库

## 包命名规则

Rocky Linux 的包按首字母分类存放在子目录中：
- 包名以 `m` 开头 → 存放在 `Packages/m/` 目录
- 包名以 `g` 开头 → 存放在 `Packages/g/` 目录
- 以此类推...

## 批量下载脚本

### 方法 1：直接下载（推荐）

```bash
#!/bin/bash
# 下载 Rocky Linux 9 RPM 包

# 设置下载目录
DOWNLOAD_DIR="packages/rockylinux9/rpm"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

# 基础 URL
BASE_URL="https://dl.rockylinux.org/vault/rocky/9.6"

# 下载 AppStream 仓库的包
wget "${BASE_URL}/AppStream/x86_64/os/Packages/m/m4-1.4.19-1.el9.x86_64.rpm"
wget "${BASE_URL}/AppStream/x86_64/os/Packages/a/autoconf-2.71-3.el9.noarch.rpm"
wget "${BASE_URL}/AppStream/x86_64/os/Packages/a/automake-1.16.5-11.el9.noarch.rpm"
wget "${BASE_URL}/AppStream/x86_64/os/Packages/b/bison-3.7.4-5.el9.x86_64.rpm"

# 尝试从 BaseOS 下载 gettext
wget "${BASE_URL}/BaseOS/x86_64/os/Packages/g/gettext-0.22.5-2.el9.x86_64.rpm" || \
wget "${BASE_URL}/AppStream/x86_64/os/Packages/g/gettext-0.22.5-2.el9.x86_64.rpm"

echo "下载完成！"
```

### 方法 2：使用 repotrack（需要在 Rocky Linux 系统上运行）

```bash
#!/bin/bash
# 使用 repotrack 下载包及其依赖

# 安装 yum-utils（如果未安装）
dnf install -y yum-utils

# 创建下载目录
mkdir -p packages/rockylinux9/rpm
cd packages/rockylinux9/rpm

# 下载包及其依赖
repotrack m4 gettext autoconf automake bison libxml2-devel libxslt-devel

echo "下载完成！包含所有依赖项"
```

### 方法 3：使用 dnf download（需要在 Rocky Linux 系统上运行）

```bash
#!/bin/bash
# 使用 dnf download 下载包（不含依赖）

mkdir -p packages/rockylinux9/rpm
cd packages/rockylinux9/rpm

# 下载指定版本的包
dnf download m4-1.4.19-1.el9 \
             gettext-0.22.5-2.el9 \
             autoconf-2.71-3.el9 \
             automake-1.16.5-11.el9 \
             bison-3.7.4-5.el9 \
             libxml2-devel \
             libxslt-devel

echo "下载完成！"
```

## 查找包的具体版本

如果需要查找包的确切版本号和文件名，可以：

### 1. 浏览器访问
直接访问对应目录：
```
https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/[首字母]/
```

### 2. 使用 curl 列出目录
```bash
curl -s https://dl.rockylinux.org/vault/rocky/9.6/AppStream/x86_64/os/Packages/m/ | grep -o 'href="[^"]*\.rpm"' | sed 's/href="//;s/"//'
```

### 3. 在 Rocky Linux 系统上查询
```bash
dnf list available m4 gettext autoconf automake bison
dnf list available libxml2-devel libxslt-devel
```

## 注意事项

1. **版本号可能变化**：随着系统更新，包的小版本号可能会变化（如 `-1.el9` 变为 `-2.el9`）
2. **依赖关系**：某些包可能有依赖，建议使用 `repotrack` 或 `dnf download --resolve` 下载完整依赖
3. **架构选择**：
   - `x86_64.rpm` - 64位 x86 架构
   - `noarch.rpm` - 架构无关包
   - `i686.rpm` - 32位 x86 架构（通常不需要）
4. **CRB 仓库**：开发包（`-devel`）通常在 CRB 仓库中，可能需要启用该仓库

## 验证下载的包

下载完成后，建议验证包的完整性：

```bash
# 检查 RPM 包签名
rpm -K *.rpm

# 查看包信息
rpm -qip package-name.rpm

# 查看包依赖
rpm -qpR package-name.rpm
```

## 离线安装

下载完成后，在离线环境安装：

```bash
# 安装单个包
rpm -ivh package-name.rpm

# 批量安装（会自动解决依赖）
rpm -ivh *.rpm

# 或使用 dnf 本地安装
dnf localinstall *.rpm
```

## 参考链接

- Rocky Linux 官方镜像：https://dl.rockylinux.org/
- Rocky Linux 文档：https://docs.rockylinux.org/
- 包搜索工具：https://pkgs.org/
