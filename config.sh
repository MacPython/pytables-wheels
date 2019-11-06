# Define custom utilities
# Test for OSX with [ -n "$IS_OSX" ]
LZO_VERSION=2.09

function build_wheel {
    local repo_dir=${1:-$REPO_DIR}
    if [ -z "$IS_OSX" ]; then
        build_linux_wheel $@
    else
        build_osx_wheel $@
    fi
}

function build_libs {
    build_bzip2
    build_lzo
    build_hdf5_threadsafe
}

function build_hdf5_threadsafe {
    if [ -e hdf5-stamp ]; then return; fi
    build_zlib
    # libaec is a drop-in replacement for szip
    build_libaec
    local hdf5_url=https://support.hdfgroup.org/ftp/HDF5/releases
    local short=$(echo $HDF5_VERSION | awk -F "." '{printf "%d.%d", $1, $2}')
    fetch_unpack $hdf5_url/hdf5-$short/hdf5-$HDF5_VERSION/src/hdf5-$HDF5_VERSION.tar.gz
    (cd hdf5-$HDF5_VERSION \
        && ./configure --with-szlib=$BUILD_PREFIX --prefix=$BUILD_PREFIX \
        --enable-threadsafe --enable-unsupported --with-pthread=yes \
        && make -j4 \
        && make install)
    touch hdf5-stamp
}

function build_linux_wheel {
    build_libs
    # Add workaround for auditwheel bug:
    # https://github.com/pypa/auditwheel/issues/29
    local bad_lib="/usr/local/lib/libhdf5.so"
    if [ -z "$(readelf --dynamic $bad_lib | grep RUNPATH)" ]; then
        patchelf --set-rpath $(dirname $bad_lib) $bad_lib
    fi
    export CFLAGS="-std=gnu99 $CFLAGS"
    export DISABLE_AVX2="True"  # wheels should never have AVX2 enabled
    build_bdist_wheel $@
}

function build_osx_wheel {
    local repo_dir=${1:-$REPO_DIR}
    local wheelhouse=$(abspath ${WHEEL_SDIR:-wheelhouse})
    # Build dual arch wheel
    export CC=clang
    export CXX=clang++
    install_pkg_config
    # 64-bit wheel
    export CFLAGS="-arch x86_64"
    export CXXFLAGS="$CFLAGS"
    export FFLAGS="$CFLAGS"
    export LDFLAGS="$CFLAGS"
    unset LDSHARED
    # Build libraries
    source multibuild/library_builders.sh
    build_libs
    # Build wheel
    local py_ld_flags="-Wall -undefined dynamic_lookup -bundle"
    export LDFLAGS="$LDFLAGS $py_ld_flags"
    export LDSHARED="clang $LDFLAGS $py_ld_flags"
    export DISABLE_AVX2="True"  # wheels should never have AVX2 enabled
    build_pip_wheel "$repo_dir"
}

function run_tests {
    # Runs tests on installed distribution from an empty directory
    python -m tables.tests.test_all
}
