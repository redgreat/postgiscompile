# PostgreSQL 安装前系统检查报告

生成时间: 2025年12月17日 10:04:34
数据目录: /opt/postgresql/data
挂载点: /


## 系统信息

- 操作系统: Rocky Linux 9.7 (Blue Onyx)
- 内核版本: 5.14.0-611.5.1.el9_7.x86_64
- 运行时间: 3 min
- 虚拟化: Hyper-V

## CPU 信息

- 型号: 13th Gen Intel(R) Core(TM) i5-13600KF
- 架构: x86_64
- 核心数: 2
- Intel 代数: 13th Gen

## 内存信息

- 总内存: 3.6Gi
- 可用内存: 3.0Gi
- 交换分区: 3.9Gi

## 磁盘信息

### 磁盘列表

- /dev/sda: 100G - Virtual Disk

### 分区布局

```
NAME          SIZE TYPE FSTYPE      MOUNTPOINT
sda           100G disk             
├─sda1        600M part vfat        /boot/efi
├─sda2          1G part xfs         /boot
└─sda3       98.4G part LVM2_member 
  ├─rlm-root 63.5G lvm  xfs         /
  ├─rlm-swap  3.9G lvm  swap        [SWAP]
  └─rlm-home   31G lvm  xfs         /home
sr0          1024M rom              
```

## 数据目录挂载点信息

**目标路径:** /opt/postgresql/data
**状态:** ⚠️ 目录不存在
**实际测试目录:** /opt
**挂载点:** /

- 设备: /dev/mapper/rlm-root
- 文件系统: xfs
- 总容量: 63.4G
- 可用空间: 60.5G
- 使用率: 5%

**底层块设备:** /dev/sda
- 磁盘大小: 100G
- 磁盘型号: Virtual Disk

## 磁盘 IO 性能测试

**测试目标:** /opt
**说明:** 数据目录不存在,测试父目录 /opt

### 测试结果

| 测试项目 | 性能指标 |
|---------|---------|
| 顺序写带宽 | 3507MiB/s |
| 顺序读带宽 | 3710MiB/s |
| 随机读 IOPS | 270k |
| 随机写 IOPS | 207k |

### 性能评估

- **磁盘类型:** 企业级 NVMe SSD
- **性能评分:** ⭐⭐⭐⭐⭐
- **建议:** ✅ 强烈推荐用于 PostgreSQL 生产环境

---
报告生成完成
