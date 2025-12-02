# postgiscomplie
postgis编译问题解决

CentOS7 编译 PostgreSQL 17 + PostGIS 3.5.3 指南

问题现象
- 在编译 PostGIS 的 `raster`/`raster2pgsql` 过程中，链接阶段出现大量 `undefined reference to 'GDAL*' / 'OGR_*'` 错误。
- 这通常意味着没有把 `libgdal` 及其依赖正确传给链接器，或错误覆盖了 `LIBS`。

核心原因
- 使用了 `make LIBS="$LDLIBS"` 之类的命令，导致 `LIBS` 为空，`-lgdal` 未被加入链接。
- 手工覆盖 `LIBS` 会破坏 `./configure` 自动探测的库列表，尤其静态 `libgdal.a` 需要一长串依赖库。

一键编译脚本
- 已提供 `script/build_postgis_centos7.sh`，在 CentOS7 上执行该脚本即可完成检查、配置与编译：

```
POSTGIS_SRC=/pgsoft/pg17.5_postgis3.5.3/postgis-3.5.3 \
PG_CONFIG=/usr/local/pgsql/bin/pg_config \
GEOS_CONFIG=/usr/local/geos/bin/geos-config \
GDAL_CONFIG=/usr/local/gdal/bin/gdal-config \
PROJ_DIR=/usr/local/proj \
bash script/build_postgis_centos7.sh
```

脚本要点
- 使用 `gdal-config` 提供库与依赖，不手动覆盖 `LIBS`。
- 仅执行标准 `make -j$(nproc)`，避免将 `LIBS` 设为无效值。

手动编译的正确步骤（如不使用脚本）
- 清理：
```
make clean
```
- 配置：
```
./configure \
  --with-pgconfig=/usr/local/pgsql/bin/pg_config \
  --with-geosconfig=/usr/local/geos/bin/geos-config \
  --with-projdir=/usr/local/proj \
  --with-gdalconfig=/usr/local/gdal/bin/gdal-config \
  --without-protobuf
```
- 编译：
```
make -j$(nproc)
```

常见排障
- 查看 `gdal-config`：
```
gdal-config --version --libs
```
- 确认系统能找到 `libgdal.so`：
```
ldconfig -p | grep gdal
```
- 如果仍旧 `undefined reference`：
  - 不要使用 `make LIBS="$LDLIBS"`。
  - 尝试显式传入 `gdal-config` 的库列表：
```
make LIBS="$(/usr/local/gdal/bin/gdal-config --libs) -lstdc++"
```
- 运行期设置库路径（避免执行阶段找不到动态库）：
```
export LD_LIBRARY_PATH=/usr/local/gdal/lib:/usr/local/geos/lib:/usr/local/proj/lib:$LD_LIBRARY_PATH
```

多版本 libtiff 的处理
- 现象：GDAL 编译时使用了新版本 libtiff（如 `libtiff.so.5`），系统默认仍有旧版（如 `libtiff.so.4`）。PostGIS 链接 `raster2pgsql` 时可能误选旧版，导致 `libgdal.so` 中对 `TIFF*` 的符号解析失败。
- 解决：优先指定新版本 libtiff 的库目录，并写入 rpath：
```
export TIFF_LIB_DIR=/usr/local/tiff/lib
export LDFLAGS="-L$TIFF_LIB_DIR -Wl,-rpath,$TIFF_LIB_DIR"
./configure \
  --with-pgconfig=/usr/local/pgsql/bin/pg_config \
  --with-geosconfig=/usr/local/geos/bin/geos-config \
  --with-projdir=/usr/local/proj \
  --with-gdalconfig=/usr/local/gdal/bin/gdal-config \
  --without-protobuf
make -j$(nproc)
```
- 也可以将新库目录注册到系统动态链接器：
```
echo /usr/local/tiff/lib | sudo tee /etc/ld.so.conf.d/libtiff5.conf
sudo ldconfig
```
- 快速确认 GDAL 依赖的 libtiff 是否正确：
```
ldd /usr/local/gdal/lib/libgdal.so | grep libtiff
```

说明
- 脚本与文档仅针对编译链接问题，未涵盖运行期扩展安装与数据库初始化步骤。
