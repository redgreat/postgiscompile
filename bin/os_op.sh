#### 关闭防火墙
```bash
systemctl stop firewalld
systemctl disable firewalld
systemctl status firewalld
```

#### 关闭SELinux
```bash
# 查看状态
getenforce

# 临时关闭
setenforce 0

# 永久关闭
vim /etc/selinux/config
# 修改为：SELINUX=disabled

# 重启系统
reboot
```

#### 关闭swap
```bash
# 查看swap状态
swapon --show

# 临时关闭
swapoff -a

# 永久关闭
vim /etc/fstab
# 注释掉swap相关行

### 1.3 内核参数优化

```bash
vim /etc/sysctl.conf
```

添加以下内容：
```bash
# for mysql
fs.aio-max-nr = 1048576
fs.file-max = 681574400
kernel.shmmax = 137438953472
kernel.shmmni = 4096
kernel.sem = 250 32000 100 200
net.ipv4.ip_local_port_range = 9000 65000
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048586
vm.swappiness = 0
net.ipv4.ip_forward = 1
net.ipv4.ip_nonlocal_bind = 1
```

应用配置：
```bash
sysctl -p
```

添加以下内容：
```bash
mysql soft nproc 65536
mysql hard nproc 65536
mysql soft nofile 65536
mysql hard nofile 65536
```

### 1.4 时区设置

```bash
export TZ=CST-8
yum install ntpdate -y
ntpdate cn.ntp.org.cn
```

### 1.5 关闭透明大页

```bash
echo never > /sys/kernel/mm/transparent_hugepage/enabled
```

### 1.6 用户相关配置

```bash
vim /etc/pam.d/login
```

添加以下内容：
```bash
session required /usr/lib64/security/pam_limits.so
session required pam_limits.so
```

```bash
vim /etc/profile