#!/usr/bin/env bash
set -euxo pipefail

# Refresh Autotools platform detection before configure.
cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" ./build-aux/config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" ./build-aux/config.sub

# Make is an explicit channel build. It uses the self-hosted compiler and
# binutils interfaces plus the seed sysroot; no host headers or libraries are
# intended to enter the result.
: "${SYSROOT_TRIPLET:?rattler-build must provide sysroot_triplet}"
SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"

export CC="${BUILD_PREFIX}/bin/gcc"
export PATH="${BUILD_PREFIX}/bin:${PATH}"
test -x "${BUILD_PREFIX}/bin/x86_64-pc-linux-gnu-as"
test -x "${BUILD_PREFIX}/bin/x86_64-pc-linux-gnu-ld"

export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
export CPPFLAGS="--sysroot=${SYSROOT}"
export LDFLAGS="--sysroot=${SYSROOT} -static-libgcc"

./configure \
  --prefix="${PREFIX}" \
  --disable-dependency-tracking

# GNU Make's source tree can bootstrap itself without an existing make.
bash build.sh
./make check
./make install
