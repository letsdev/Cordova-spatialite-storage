#!/bin/bash
#
# Rebuilds the native iOS libraries of this plugin from source and packs them as
# xcframeworks containing a device slice (arm64) and a simulator slice
# (arm64 + x86_64). A plain fat .a cannot hold two arm64 slices, which is why
# Apple Silicon simulators need xcframeworks.
#
# Library versions are pinned to what the plugin has shipped since 2015 so the
# runtime behaviour stays identical. SQLite compile options and the SpatiaLite
# feature set (GEOS, PROJ, libxml2, GeoPackage; no FreeXL, no LWGEOM) mirror
# the previous binaries.
#
# Usage:
#   scripts/build-ios-xcframeworks.sh [build|pack|all] [target ...]
#     targets: device-arm64 sim-arm64 sim-x86_64 (default: all three)
# Environment:
#   WORK     scratch directory for sources and intermediate builds
#            (default: <repo>/build-ios, gitignored)
#   OUT      where the xcframeworks are written (default: src/ios/native)
#   MIN_IOS  deployment target (default: 13.0)
#   JOBS     parallel make jobs (default: number of CPUs)
#   FORCE=1  rebuild libraries that already exist in the target prefix
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-${repo_root}/build-ios}"
OUT="${OUT:-${repo_root}/src/ios/native}"
MIN_IOS="${MIN_IOS:-13.0}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

SQLITE_NAME=sqlite-autoconf-3081100
SQLITE_URL=https://www.sqlite.org/2015/${SQLITE_NAME}.tar.gz
SQLITE_SHA=89640082f56b0aec1e691ba4976fb592ac905c791e616905d0a5f0c38e88b616
PROJ_NAME=proj-4.8.0
PROJ_URL=https://download.osgeo.org/proj/${PROJ_NAME}.tar.gz
PROJ_SHA=2db2dbf0fece8d9880679154e0d6d1ce7c694dd8e08b4d091028093d87a9d1b5
GEOS_NAME=geos-3.4.2
GEOS_URL=https://download.osgeo.org/geos/${GEOS_NAME}.tar.bz2
GEOS_SHA=15e8bfdf7e29087a957b56ac543ea9a80321481cef4d4f63a7b268953ad26c53
SPATIALITE_NAME=libspatialite-4.3.0a
SPATIALITE_URL=https://www.gaia-gis.it/gaia-sins/libspatialite-sources/${SPATIALITE_NAME}.tar.gz
SPATIALITE_SHA=88900030a4762904a7880273f292e5e8ca6b15b7c6c3fb88ffa9e67ee8a5a499

LIBS_OUT="libsqlite3 libproj libgeos libgeos_c libspatialite"
ALL_TARGETS="device-arm64 sim-arm64 sim-x86_64"

log() { printf '\n==> %s\n' "$*"; }

fetch() {
  local url="$1" sha="$2" file="${WORK}/dl/$(basename "$1")"
  mkdir -p "${WORK}/dl"
  if [ ! -f "${file}" ]; then
    log "Downloading $(basename "${url}")"
    curl -fsSL --retry 3 -o "${file}" "${url}"
  fi
  local actual
  actual="$(shasum -a 256 "${file}" | awk '{print $1}')"
  if [ "${actual}" != "${sha}" ]; then
    echo "Checksum mismatch for ${file}: ${actual}" >&2
    exit 1
  fi
}

extract() {
  # extract <archive> <destination dir of the unpacked tree>
  local file="${WORK}/dl/$(basename "$1")" dest="$2"
  rm -rf "${dest}"
  mkdir -p "$(dirname "${dest}")"
  case "${file}" in
    *.tar.bz2) tar -xjf "${file}" -C "$(dirname "${dest}")" ;;
    *)         tar -xzf "${file}" -C "$(dirname "${dest}")" ;;
  esac
}

setup_target() {
  TARGET="$1"
  case "${TARGET}" in
    device-arm64) PLATFORM=iphoneos;        ARCH=arm64;  HOST=arm-apple-darwin;    TRIPLE="arm64-apple-ios${MIN_IOS}" ;;
    sim-arm64)    PLATFORM=iphonesimulator; ARCH=arm64;  HOST=arm-apple-darwin;    TRIPLE="arm64-apple-ios${MIN_IOS}-simulator" ;;
    sim-x86_64)   PLATFORM=iphonesimulator; ARCH=x86_64; HOST=x86_64-apple-darwin; TRIPLE="x86_64-apple-ios${MIN_IOS}-simulator" ;;
    *) echo "unknown target ${TARGET}" >&2; exit 1 ;;
  esac
  SDK="$(xcrun --sdk "${PLATFORM}" --show-sdk-path)"
  TDIR="${WORK}/${TARGET}"
  PREFIX="${TDIR}/prefix"
  mkdir -p "${PREFIX}/lib" "${PREFIX}/include"

  export CC="$(xcrun --sdk "${PLATFORM}" -f clang)"
  export CXX="$(xcrun --sdk "${PLATFORM}" -f clang++)"
  export AR="$(xcrun --sdk "${PLATFORM}" -f ar)"
  export RANLIB="$(xcrun --sdk "${PLATFORM}" -f ranlib)"
  export NM="$(xcrun --sdk "${PLATFORM}" -f nm)"
  export STRIP="$(xcrun --sdk "${PLATFORM}" -f strip)"
  # -target/-isysroot also in CPPFLAGS so configure's preprocessor checks see the SDK headers
  export CPPFLAGS="-target ${TRIPLE} -isysroot ${SDK} -I${PREFIX}/include -I${SDK}/usr/include/libxml2"
  export CFLAGS="-target ${TRIPLE} -isysroot ${SDK} -O2 -fPIC -Wno-error"
  export CXXFLAGS="${CFLAGS} -std=c++11 -stdlib=libc++"
  export LDFLAGS="-target ${TRIPLE} -isysroot ${SDK} -L${PREFIX}/lib"
  # keep homebrew/system pkg-config results out of the cross build
  export PKG_CONFIG_LIBDIR="${TDIR}/no-pkgconfig"
  export PKG_CONFIG_PATH=""
}

build_sqlite() {
  if [ -f "${PREFIX}/lib/libsqlite3.a" ] && [ "${FORCE:-0}" != 1 ]; then log "[${TARGET}] libsqlite3.a exists, skipping"; return; fi
  local src="${TDIR}/src/${SQLITE_NAME}"
  log "[${TARGET}] SQLite"
  extract "${SQLITE_URL}" "${src}"
  ( cd "${src}" && "${CC}" ${CFLAGS} \
      -DSQLITE_THREADSAFE=1 \
      -DSQLITE_ENABLE_FTS3 \
      -DSQLITE_ENABLE_FTS3_PARENTHESIS \
      -DSQLITE_ENABLE_RTREE \
      -DSQLITE_MAX_MMAP_SIZE=0 \
      -DHAVE_USLEEP=1 -DHAVE_LOCALTIME_R=1 -DHAVE_GMTIME_R=1 \
      -c sqlite3.c -o sqlite3.o
    rm -f "${PREFIX}/lib/libsqlite3.a"
    "${AR}" rcs "${PREFIX}/lib/libsqlite3.a" sqlite3.o
    cp sqlite3.h sqlite3ext.h "${PREFIX}/include/" )
}

build_proj() {
  if [ -f "${PREFIX}/lib/libproj.a" ] && [ "${FORCE:-0}" != 1 ]; then log "[${TARGET}] libproj.a exists, skipping"; return; fi
  local src="${TDIR}/src/${PROJ_NAME}"
  log "[${TARGET}] PROJ"
  extract "${PROJ_URL}" "${src}"
  ( cd "${src}" \
    && ./configure --host="${HOST}" --prefix="${PREFIX}" \
         --disable-shared --enable-static --without-jni \
         > configure.log 2>&1 \
    && make -j"${JOBS}" -C src > make.log 2>&1 \
    && make -C src install > install.log 2>&1 )
}

build_geos() {
  if [ -f "${PREFIX}/lib/libgeos_c.a" ] && [ "${FORCE:-0}" != 1 ]; then log "[${TARGET}] libgeos_c.a exists, skipping"; return; fi
  local src="${TDIR}/src/${GEOS_NAME}"
  log "[${TARGET}] GEOS"
  extract "${GEOS_URL}" "${src}"
  ( cd "${src}" \
    && ./configure --host="${HOST}" --prefix="${PREFIX}" \
         --disable-shared --enable-static --disable-dependency-tracking \
         > configure.log 2>&1 \
    && make -j"${JOBS}" -C include > make-include.log 2>&1 \
    && make -j"${JOBS}" -C src > make-src.log 2>&1 \
    && make -j"${JOBS}" -C capi > make-capi.log 2>&1 \
    && make -C include install > install.log 2>&1 \
    && make -C src install >> install.log 2>&1 \
    && make -C capi install >> install.log 2>&1 \
    && make -C tools install >> install.log 2>&1 )
}

# configure resets LIBS from geos-config, so the static dependencies of libgeos_c
# (libgeos, libc++) and the other libraries go through LDFLAGS instead.
# libxml2 comes from the iOS SDK; LIBXML2_* bypasses the pkg-config lookup.
build_spatialite() {
  if [ -f "${PREFIX}/lib/libspatialite.a" ] && [ "${FORCE:-0}" != 1 ]; then log "[${TARGET}] libspatialite.a exists, skipping"; return; fi
  local src="${TDIR}/src/${SPATIALITE_NAME}"
  log "[${TARGET}] SpatiaLite"
  extract "${SPATIALITE_URL}" "${src}"
  # The iOS SDK ships iconv.h but no localcharset.h (GNU libiconv extension).
  # The locale charset on iOS is always UTF-8, so provide locale_charset() inline.
  for f in src/gaiaaux/gg_utf8.c src/gaiageo/gg_shape.c; do
    sed -i '' 's|#include <localcharset.h>|static const char *locale_charset (void) { return "UTF-8"; }|' "${src}/${f}"
  done
  ( cd "${src}" \
    && LDFLAGS="${LDFLAGS} -lgeos_c -lgeos -lc++ -lsqlite3 -lproj -lxml2 -liconv -lz" \
       LIBXML2_CFLAGS="-I${SDK}/usr/include/libxml2" LIBXML2_LIBS="-lxml2" \
       ./configure --host="${HOST}" --prefix="${PREFIX}" \
         --disable-shared --enable-static --disable-dependency-tracking \
         --with-geosconfig="${PREFIX}/bin/geos-config" \
         --enable-geos --enable-geosadvanced --enable-proj --enable-iconv \
         --enable-libxml2 --enable-geopackage --enable-epsg --enable-mathsql \
         --enable-freexl=no --enable-lwgeom=no --enable-gcp=no \
         --enable-geocallbacks=no --enable-examples=no \
         > configure.log 2>&1 \
    && make -j"${JOBS}" -C src > make.log 2>&1 \
    && make -C src install > install.log 2>&1 )
}

build_target() {
  setup_target "$1"
  log "Building ${TARGET} (${TRIPLE}, SDK $(basename "${SDK}"))"
  build_sqlite
  build_proj
  build_geos
  build_spatialite
  for lib in ${LIBS_OUT}; do
    test -f "${PREFIX}/lib/${lib}.a" || { echo "missing ${PREFIX}/lib/${lib}.a" >&2; exit 1; }
    lipo -info "${PREFIX}/lib/${lib}.a"
  done
  touch "${TDIR}/.done"
}

pack() {
  for t in ${ALL_TARGETS}; do
    test -f "${WORK}/${t}/.done" || { echo "target ${t} has not been built" >&2; exit 1; }
  done
  local fat="${WORK}/sim-fat"
  mkdir -p "${fat}" "${OUT}"
  for lib in ${LIBS_OUT}; do
    log "Packing ${lib}.xcframework"
    lipo -create \
      "${WORK}/sim-arm64/prefix/lib/${lib}.a" \
      "${WORK}/sim-x86_64/prefix/lib/${lib}.a" \
      -output "${fat}/${lib}.a"
    rm -rf "${OUT}/${lib}.xcframework"
    xcodebuild -create-xcframework \
      -library "${WORK}/device-arm64/prefix/lib/${lib}.a" \
      -library "${fat}/${lib}.a" \
      -output "${OUT}/${lib}.xcframework" > /dev/null
    plutil -extract AvailableLibraries json -o - "${OUT}/${lib}.xcframework/Info.plist" \
      | tr -d '\n ' | sed -E 's/"HeadersPath":"[^"]*",?//g'
    echo
  done
}

mode="${1:-all}"
[ $# -gt 0 ] && shift
targets="${*:-${ALL_TARGETS}}"

case "${mode}" in
  build|all)
    for url_sha in "${SQLITE_URL} ${SQLITE_SHA}" "${PROJ_URL} ${PROJ_SHA}" "${GEOS_URL} ${GEOS_SHA}" "${SPATIALITE_URL} ${SPATIALITE_SHA}"; do
      # shellcheck disable=SC2086
      fetch ${url_sha}
    done
    for t in ${targets}; do
      build_target "${t}"
    done
    [ "${mode}" = "all" ] && pack
    ;;
  pack)
    pack
    ;;
  *)
    echo "usage: $0 [build|pack|all] [target ...]" >&2
    exit 1
    ;;
esac
log "Done"
