#!/usr/bin/env bash
set -euxo pipefail

# Binutils builds out-of-tree.
mkdir -p "${SRC_DIR}/build"
cd "${SRC_DIR}/build"

# This recipe is itself an explicit channel build even though the installed
# tools will default to host paths. The sysroot keeps the build reproducible
# and prevents host headers/libraries from leaking into the binaries.
: "${SYSROOT_TRIPLET:?rattler-build must provide sysroot_triplet}"
SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"

# Use the previous stage's compiler interface and assembler/linker interface.
# The build prefix is ahead of host paths in rattler-build's environment.
export CC="${BUILD_PREFIX}/bin/gcc"
export CXX="${BUILD_PREFIX}/bin/g++"
export PATH="${BUILD_PREFIX}/bin:${PATH}"
test -x "${BUILD_PREFIX}/bin/as"
test -x "${BUILD_PREFIX}/bin/ld"

export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe -fPIC"
export CXXFLAGS="--sysroot=${SYSROOT} -O2 -pipe -fPIC"
export CPPFLAGS="--sysroot=${SYSROOT}"
export LDFLAGS="--sysroot=${SYSROOT} -Wl,-rpath,${PREFIX}/lib -static-libstdc++ -static-libgcc"

../configure \
  --prefix="${PREFIX}" \
  --libdir="${PREFIX}/lib" \
  --build=x86_64-pc-linux-gnu \
  --host=x86_64-pc-linux-gnu \
  --target=x86_64-pc-linux-gnu \
  --enable-ld=default \
  --enable-plugins \
  --enable-lto \
  --disable-multilib \
  --disable-sim \
  --disable-gdb \
  --disable-nls \
  --disable-gprofng \
  --disable-werror \
  --without-zstd

make -j"${CPU_COUNT}"
make install-strip

# GCC searches first for target-prefixed tools. Keep the ordinary native names
# for host-integrating use and add matching x86_64-pc-linux-gnu aliases.
for tool in \
  addr2line ar as c++filt elfedit gprof ld ld.bfd nm objcopy objdump \
  ranlib readelf size strings strip; do
  test -x "${PREFIX}/bin/${tool}"
  ln -sfn -- "${tool}" "${PREFIX}/bin/x86_64-pc-linux-gnu-${tool}"
done
