# PostGISCompile

面向 **RHEL / CentOS / Rocky 8/9** 离线环境，提供 PostgreSQL + PostGIS 编译安装、**多块普盘软 RAID 存储搭建**，以及轻量监控与企业微信告警（无需 Grafana/Prometheus）。

## 核心能力

- **离线安装**：本地 RPM 仓库、`postgresql-custom` systemd 服务、扩展与安全认证模板
- **存储优化**：`mdadm` RAID10 数据盘，可选 WAL 独立 RAID1（6 盘场景）
- **安装前检查**：`preinstall_report.sh` 采集 CPU/内存/磁盘并执行 fio
- **监控告警**：见 [`monitor/DEPLOY.md`](monitor/DEPLOY.md)

## 目录速览

| 路径 | 说明 |
|------|------|
| `bin/install.sh` | PostgreSQL / PostGIS 主编译安装脚本 |
| `bin/storage_plan.sh` | 存储方案规划（只读，生成 Markdown 报告） |
| `bin/storage_setup.sh` | 执行 mdadm + XFS + 挂载 + fstab（**会清空磁盘**） |
| `bin/storage_verify.sh` | 存储验收：阵列、挂载、fstab、目录权限 |
| `bin/preinstall_report.sh` | 安装前系统与 IO 检测报告 |
| `config/*.template` | `postgresql.conf`、`pg_hba.conf` 等模板 |
| `packages/rhel8\|rhel9/` | 离线 RPM 包 |
| `monitor/` | 监控脚本、systemd、SQL、测试 |

安装后存储环境文件（由 `storage_setup.sh` 写入）：

`/etc/postgiscompile/storage.env` — `install.sh` 会自动读取其中的 `PG_DATA_DIR`、`PG_WAL_DIR` 等。

---

## 存储方案说明

| 布局 | 盘数 | 数据 | WAL | 适用 |
|------|------|------|-----|------|
| `4all` | 4 | RAID10 ×4 | 与数据同卷 | 仅 4 块数据盘，实现简单 |
| `6split` | 6 | RAID10 ×4 | RAID1 ×2，挂载 `/pgwal` | WAL 与数据 IO 隔离（推荐有 6 盘时） |

- **4 盘**无法同时做「数据 RAID10」+「WAL RAID10」，WAL 单独 RAID10 需 8 盘及以上。
- WAL 重 **延迟与隔离**，容量需求小；6 盘时用 **2 盘 RAID1** 即可，不必为 WAL 再要 4 盘 RAID10。

---

## 四盘安装流程（`4all`）

假设 4 块空闲盘为 `/dev/sdb`～`/dev/sde`（**请按 `lsblk` 实际盘符修改**），系统盘不参与阵列。

### 1. 克隆项目并进入目录

```bash
cd /path/to/postgiscompile
```

### 2. 存储规划（只读）

```bash
sudo bash bin/storage_plan.sh \
  --layout 4all \
  --disk /dev/sdb /dev/sdc /dev/sdd /dev/sde \
  --pg-data-dir /opt/postgresql/data \
  --yes
```

报告：`docs/storage_plan_*.md`

### 3. 预演搭建（不写盘）

```bash
sudo bash bin/storage_setup.sh \
  --layout 4all \
  --disk /dev/sdb /dev/sdc /dev/sdd /dev/sde \
  --yes \
  --dry-run
```

### 4. 正式搭建 RAID（破坏性）

```bash
sudo bash bin/storage_setup.sh \
  --layout 4all \
  --disk /dev/sdb /dev/sdc /dev/sdd /dev/sde \
  --yes
```

- 默认需输入 `DESTROY` 确认；`--yes` 跳过确认。
- 结果：RAID10 挂载 `/opt/postgresql`，数据目录 `/opt/postgresql/data`，WAL 在数据卷内 `pg_wal`。

### 5. 存储验收

```bash
sudo bash bin/storage_verify.sh
```

报告：`docs/storage_verify_*.md`。存在 **FAIL** 时退出码为 1，请先修复再继续。

### 6. IO 与系统检测

```bash
sudo bash bin/preinstall_report.sh
```

按提示确认数据目录为 `/opt/postgresql/data`，查看 fio 结果是否满足预期。

### 7. 安装 PostgreSQL / PostGIS

```bash
sudo bash bin/install.sh
```

自动读取 `/etc/postgiscompile/storage.env`；机械盘场景会调整 `random_page_cost` 等参数。

### 8. 验证服务

```bash
systemctl status postgresql-custom
/opt/postgresql/postgres/bin/psql -U postgres -h localhost -c "SELECT version();"
```

### 9.（可选）部署监控

参见 [`monitor/DEPLOY.md`](monitor/DEPLOY.md)。

---

## 六盘安装流程（`6split`）

6 块盘示例：`sdb`～`sdg` — 前 4 块数据 RAID10，后 2 块 WAL RAID1。

| 角色 | 磁盘示例 |
|------|----------|
| 数据 RAID10 | `/dev/sdb` `/dev/sdc` `/dev/sdd` `/dev/sde` |
| WAL RAID1 | `/dev/sdf` `/dev/sdg` |

### 1. 存储规划

```bash
sudo bash bin/storage_plan.sh \
  --layout 6split \
  --disk /dev/sdb /dev/sdc /dev/sdd /dev/sde /dev/sdf /dev/sdg \
  --pg-data-dir /opt/postgresql/data \
  --pg-wal-dir /pgwal \
  --yes
```

### 2. 预演 + 正式搭建

```bash
sudo bash bin/storage_setup.sh \
  --layout 6split \
  --disk /dev/sdb /dev/sdc /dev/sdd /dev/sde /dev/sdf /dev/sdg \
  --pg-wal-dir /pgwal \
  --dry-run

sudo bash bin/storage_setup.sh \
  --layout 6split \
  --disk /dev/sdb /dev/sdc /dev/sdd /dev/sde /dev/sdf /dev/sdg \
  --pg-wal-dir /pgwal \
  --yes
```

- 数据：RAID10 → `/opt/postgresql`
- WAL：RAID1 → `/pgwal`
- `install.sh` 执行 `initdb` 时会自动加 `--waldir=/pgwal`

### 3. 验收 → IO 检测 → 安装

```bash
sudo bash bin/storage_verify.sh --layout 6split
sudo bash bin/preinstall_report.sh
sudo bash bin/install.sh
```

`storage_verify.sh` 会检查 WAL 挂载点、`fstab` 及目录权限是否与 `6split` 一致。

---

## 流程总览

```mermaid
flowchart LR
  A[storage_plan] --> B[storage_setup dry-run]
  B --> C[storage_setup]
  C --> D[storage_verify]
  D --> E[preinstall_report]
  E --> F[install.sh]
  F --> G[monitor 可选]
```

| 步骤 | 脚本 | 说明 |
|------|------|------|
| 规划 | `storage_plan.sh` | 只读，确认盘符与布局 |
| 搭建 | `storage_setup.sh` | 写盘，生成 `storage.env` |
| 验收 | `storage_verify.sh` | md / 挂载 / fstab / 权限 |
| 检测 | `preinstall_report.sh` | fio + 硬件报告 |
| 安装 | `install.sh` | 编译安装 PG + PostGIS |

---

## 无额外数据盘时（快速安装）

系统盘已有足够空间、不需要软 RAID 时：

```bash
sudo bash bin/preinstall_report.sh
sudo bash bin/install.sh
```

---

## 常用命令

```bash
# 查看阵列状态
cat /proc/mdstat
mdadm --detail /dev/md0

# 查看挂载
findmnt /opt/postgresql /pgwal

# 重新验收
sudo bash bin/storage_verify.sh --strict
```

---

## 注意事项

- **盘符务必人工核对**：`lsblk`、`storage_plan` 报告与 `storage_setup --dry-run` 输出一致后再执行正式搭建。
- **storage_setup 会清空成员盘**，生产环境先备份，并确保系统盘未列入 `--disk`。
- 建议监控账号授予 `pg_monitor`；对外连接建议 TLS（`sslmode=require`）。
- Windows 上 `pg_cron` 无后台工作进程，请在 Linux 实例启用或改用替代方案。

## 许可证

见 [LICENSE](LICENSE)。
