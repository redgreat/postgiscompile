#!/usr/bin/env bash
set -euo pipefail

# ===============================
# 变量默认值（可通过环境变量覆盖）
# ===============================
POSTGIS_SRC=${POSTGIS_SRC:-/pgsoft/pg17.5_postgis3.5.3/postgis-3.5.3}
PG_CONFIG=${PG_CONFIG:-/usr/local/pgsql/bin/pg_config}
GEOS_CONFIG=${GEOS_CONFIG:-/usr/local/geos/bin/geos-config}
GDAL_CONFIG=${GDAL_CONFIG:-/usr/local/gdal/bin/gdal-config}
PROJ_DIR=${PROJ_DIR:-/usr/local/proj}
JOBS=${JOBS:-$(nproc)}
TIFF_LIB_DIR=${TIFF_LIB_DIR:-/usr/local/tiff/lib}

export PATH="$(dirname "$PG_CONFIG"):$PATH"
export PATH="$(dirname "$GEOS_CONFIG"):$PATH"
export PATH="$(dirname "$GDAL_CONFIG"):$PATH"

# =====================================
# 函数：输出使用方法与关键环境变量说明（中文）
# 作用：帮助用户快速了解脚本的输入与依赖
# =====================================
usage() {
  echo "用法："
  echo "  POSTGIS_SRC=<postgis源码路径> PG_CONFIG=<pg_config路径> GEOS_CONFIG=<geos-config路径> \""
  echo "  GDAL_CONFIG=<gdal-config路径> PROJ_DIR=<proj安装目录> JOBS=<并行数> \""
  echo "  bash script/build_postgis_centos7.sh"
  echo "示例："
  echo "  POSTGIS_SRC=/pgsoft/pg17.5_postgis3.5.3/postgis-3.5.3 \""
  echo "  PG_CONFIG=/usr/local/pgsql/bin/pg_config \""
  echo "  GEOS_CONFIG=/usr/local/geos/bin/geos-config \""
  echo "  GDAL_CONFIG=/usr/local/gdal/bin/gdal-config \""
  echo "  PROJ_DIR=/usr/local/proj \""
  echo "  TIFF_LIB_DIR=/usr/local/tiff/lib \""
  echo "  bash script/build_postgis_centos7.sh"
}

# =====================================
# 函数：检查编译所需工具是否可用
# 作用：提前发现路径或依赖问题，避免链接期失败
# =====================================
check_requirements() {
  for tool in "$PG_CONFIG" "$GEOS_CONFIG" "$GDAL_CONFIG"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "缺少必要工具：$tool"
      usage
      exit 1
    fi
  done
  if [ ! -d "$PROJ_DIR" ]; then
    echo "未找到PROJ目录：$PROJ_DIR"
    exit 1
  fi
  if [ ! -d "$TIFF_LIB_DIR" ]; then
    echo "未找到TIFF库目录：$TIFF_LIB_DIR"
    echo "如系统存在多个libtiff版本，请将新版本目录赋值给TIFF_LIB_DIR"
    exit 1
  fi
  echo "pg_config: $($PG_CONFIG --version)"
  echo "GEOS: $($GEOS_CONFIG --version)"
  echo "GDAL: $($GDAL_CONFIG --version)"
  echo "GDAL libs: $($GDAL_CONFIG --libs)"
}

# =====================================
# 函数：配置PostGIS源码工程
# 作用：正确传入geos/proj/gdal路径，避免错误覆盖LIBS
# =====================================
configure_postgis() {
  cd "$POSTGIS_SRC"
  make clean || true
  export LDFLAGS="${LDFLAGS:-} -L${TIFF_LIB_DIR} -Wl,-rpath,${TIFF_LIB_DIR}"
  ./configure \
    --with-pgconfig="$PG_CONFIG" \
    --with-geosconfig="$GEOS_CONFIG" \
    --with-projdir="$PROJ_DIR" \
    --with-gdalconfig="$GDAL_CONFIG" \
    --without-protobuf
}

# =====================================
# 函数：编译PostGIS
# 作用：仅执行标准make，不人为覆盖LIBS导致链接缺库
# =====================================
build_postgis() {
  cd "$POSTGIS_SRC"
  make -j"$JOBS"
}

# =====================================
# 函数：在链接失败时提供最关键的诊断信息
# 作用：快速定位GDAL未被链接或库路径问题
# =====================================
diagnose_on_failure() {
  echo "——链接失败排查建议——"
  echo "1) 确认不使用：make LIBS=\"\$LDLIBS\"（该写法会使LIBS为空）"
  echo "2) 查看config.log中GDAL相关条目：grep -n GDAL config.log"
  echo "3) 如使用静态libgdal.a，请以\"$($GDAL_CONFIG --libs)\"覆盖所有依赖"
  echo "4) 若仍报undefined reference，可尝试：\n   make LIBS=\"$($GDAL_CONFIG --libs) -lstdc++\""
  echo "5) 多版本libtiff时，优先指定新版本目录：\n   export LDFLAGS=\"-L${TIFF_LIB_DIR} -Wl,-rpath,${TIFF_LIB_DIR}\""
  echo "6) 运行时需设置LD_LIBRARY_PATH：\n   export LD_LIBRARY_PATH=${TIFF_LIB_DIR}:/usr/local/gdal/lib:/usr/local/geos/lib:/usr/local/proj/lib:\$LD_LIBRARY_PATH"
}

# =====================================
# 函数：主流程入口
# 作用：串联检查、配置、编译与失败诊断
# =====================================
main() {
  check_requirements
  configure_postgis
  if ! build_postgis; then
    diagnose_on_failure
    exit 2
  fi
  echo "编译成功：$(date)"
}

main "$@"