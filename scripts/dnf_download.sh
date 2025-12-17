dnf download --setopt=install_weak_deps=True \
             --resolve --alldeps \
             --downloaddir=/tmp/mypkgs \
             gettext autoconf automake bison gcc gcc-c++ make tar bzip2 xz openssl-devel openssl-libs readline zlib-devel cmake libuv vim perl json-c sqlite proj geos protobuf-c libtiff libcurl binutils glibc kernel-headers libstdc++-devel krb5-libs \
             krb5-devel keyutils-libs libcom_err-devel libkadm5 libverto-devel libicu libxml2 openldap cyrus-sasl pam libselinux \
             libsepol pcre2 libxcrypt glibc pkgconf-pkg-config cpp libgomp libmpc mpfr gmp mpfr make ncurses flex proj \
             protobuf 

sudo vi /etc/NetworkManager/system-connections/eth0.nmconnection

dns=202.102.134.68;

sudo nmcli connection reload
sudo nmcli connection up eth0

dnf download --setopt=install_weak_deps=True --arch=x86_64 --resolve --alldeps \
lsof htop

dnf download --enablerepo=epel --setopt=install_weak_deps=True --arch=x86_64 --resolve --alldeps \
SFCGAL-devel

rpm -q | grep sfcgal

rpm -q sfcgal

dnf download --enablerepo=epel --setopt=install_weak_deps=True --arch=x86_64 --resolve --alldeps \
pg_repack


dnf download --setopt=install_weak_deps=True --arch=x86_64 --resolve --alldeps \
coreutils procps-ng util-linux systemd systemd-udev pciutils dmidecode smartmontools mdadm device-mapper-multipath lvm2 device-mapper fio virt-what

dnf download --enablerepo=epel --setopt=install_weak_deps=True --arch=x86_64 --resolve --alldeps pgbackrest

dnf download --setopt=install_weak_deps=True --arch=x86_64 --resolve --alldeps pgbackrest libssh2

