#!/usr/bin/env bash
set -euxo pipefail

# GCC's official prerequisite archives are fetched and verified by
# rattler-build, then extracted into these source directories.
for prerequisite in gettext gmp isl mpc mpfr; do
  test -d "${SRC_DIR}/${prerequisite}"
done

gcc_version="$(< "${SRC_DIR}/gcc/BASE-VER")"

# GCC's x86_64 multilib metadata installs target libraries under lib64 even
# with --disable-multilib. Conda prefixes use lib, so redirect both multilib
# directory names before configure runs.
while IFS= read -r -d '' tinfo_file; do
  sed -i \
    -e 's#\(MULTILIB_OSDIRNAMES.*\)lib64#\1lib#g' \
    -e 's#\(MULTILIB_OSDIRNAMES.*\)libx32#\1lib#g' \
    -- "$tinfo_file"
done < <(find "${SRC_DIR}" -type f -path '*/config/*/t-*' -print0)

# Refresh Autoconf host detection with the gnuconfig files from the build
# environment. Newer CPU and OS triples are frequently absent from GCC's
# vendored config.guess/config.sub copies.
while IFS= read -r -d '' config_script; do
  case "${config_script}" in
    */config.guess)
      cp -- "${BUILD_PREFIX}/share/gnuconfig/config.guess" "${config_script}"
      ;;
    */config.sub)
      cp -- "${BUILD_PREFIX}/share/gnuconfig/config.sub" "${config_script}"
      ;;
  esac
done < <(find "${SRC_DIR}" -type f \( -name config.guess -o -name config.sub \) -print0)

mkdir -p "${SRC_DIR}/build"
cd "${SRC_DIR}/build"

# Channel builds are explicit hermetic builds even though the installed
# compiler will later default to host-native mode.
: "${SYSROOT_TRIPLET:?rattler-build must provide sysroot_triplet}"
SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"

# The previous stage exposes the conventional compiler names through its
# gcc/gxx interface packages. Explicit paths prevent configure from choosing
# a host compiler from PATH.
export CC="${BUILD_PREFIX}/bin/gcc"
export CXX="${BUILD_PREFIX}/bin/g++"

# Keep the intermediate bootstrap carrier much smaller than a conventional
# debug build of GCC. Passing --sysroot here is important when the previous
# stage is a host-native compiler: the bootstrap itself must not accidentally
# link against the build host's headers or libraries.
export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
export CXXFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
export CPPFLAGS="--sysroot=${SYSROOT}"
export LDFLAGS="--sysroot=${SYSROOT}"

# rattler-build exports a host-prefix Python even when Python is not a host
# dependency. ISL treats that nonexistent interpreter as "too old"; Python is
# not required for this stage.
unset PYTHON

# Do not set --with-sysroot here: the installed compiler must default to
# host glibc and kernel headers. --with-build-sysroot only tells this GCC
# build where target headers/libs live while compiling the compiler itself.
../configure \
  --prefix="${PREFIX}" \
  --libdir="${PREFIX}/lib" \
  --with-slibdir="${PREFIX}/lib" \
  --with-pkgversion="black-desk's devkit GCC ${gcc_version}" \
  --with-bugurl="https://github.com/black-desk-devkit/bootstrap/issues" \
  --with-build-sysroot="${SYSROOT}" \
  --with-native-system-header-dir=/usr/include \
  --with-gxx-include-dir="${PREFIX}/include/c++/${gcc_version}" \
  --enable-languages=c,c++ \
  --enable-shared \
  --enable-threads=posix \
  --enable-__cxa-atexit \
  --enable-libgomp \
  --enable-libsanitizer \
  --enable-lto \
  --enable-plugin \
  --enable-default-pie \
  --enable-multiarch \
  --disable-bootstrap \
  --disable-multilib \
  --disable-nls \
  --disable-libssp \
  --disable-werror \
  --without-zstd

make -j"${CPU_COUNT}"
make install
