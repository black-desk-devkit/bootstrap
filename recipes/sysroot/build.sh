#!/usr/bin/env bash
set -euxo pipefail

: "${SYSROOT_TRIPLET:?rattler-build must provide sysroot_triplet}"

SYSROOT="${PREFIX}/${SYSROOT_TRIPLET}/sysroot"
mkdir -p "${SYSROOT}"

extract_rpm() {
  local archive="$1" destination="$2"
  mkdir -p "${destination}"
  rpm2cpio "${archive}" | (cd "${destination}" && cpio -idm --quiet)
}

extract_rpm glibc.rpm binary-glibc
extract_rpm glibc-devel.rpm binary-glibc-devel
extract_rpm glibc-headers.rpm binary-glibc-headers
extract_rpm glibc-static.rpm binary-glibc-static
extract_rpm glibc-common.rpm binary-glibc-common
extract_rpm glibc-gconv-extra.rpm binary-glibc-gconv-extra
extract_rpm glibc-langpack-en.rpm binary-glibc-langpack-en
extract_rpm kernel-headers.rpm binary-kernel-headers

cd "${SYSROOT}"
cp -a "${SRC_DIR}/binary-glibc/." .
mkdir -p usr/include
cp -a "${SRC_DIR}/binary-glibc-devel/usr/." usr/
cp -a "${SRC_DIR}/binary-glibc-headers/usr/." usr/
cp -a "${SRC_DIR}/binary-glibc-static/usr/." usr/
cp -a "${SRC_DIR}/binary-glibc-common/usr/." usr/
cp -a "${SRC_DIR}/binary-glibc-gconv-extra/usr/." usr/
cp -a "${SRC_DIR}/binary-glibc-langpack-en/usr/." usr/
cp -a "${SRC_DIR}/binary-kernel-headers/usr/." usr/

# Normalize the Rocky layout to the conda-style sysroot layout. Keep the
# real library directory at lib64 and provide the conventional aliases.
mkdir -p lib64 usr
if [[ -d usr/lib ]]; then
  cp -a usr/lib/. lib64/
  rm -rf usr/lib
fi
if [[ -d usr/lib64 ]]; then
  cp -a usr/lib64/. lib64/
  rm -rf usr/lib64
fi
if [[ -d lib ]]; then
  cp -a lib/. lib64/
  rm -rf lib
fi
if [[ -d bin ]]; then
  mkdir -p usr/bin
  cp -a bin/. usr/bin/
  rm -rf bin
fi
if [[ -d sbin ]]; then
  mkdir -p usr/sbin
  cp -a sbin/. usr/sbin/
  rm -rf sbin
fi
ln -s lib64 lib
ln -s ../lib64 usr/lib
ln -s ../lib64 usr/lib64
ln -s usr/bin bin
ln -s usr/sbin sbin

# These files are not part of the supported development sysroot.
rm -f lib64/libnsl*.so* usr/lib64/libnsl.{a,so} || true
rm -f usr/include/rpcsvc/yp* usr/include/rpcsvc/yp*.h || true
rm -rf usr/share/man usr/share/doc usr/lib/systemd

mkdir -p usr/share
ln -s ../../../../share/zoneinfo usr/share/zoneinfo
