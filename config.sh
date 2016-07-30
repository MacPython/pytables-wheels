# Define custom utilities
# Test for OSX with [ -n "$IS_OSX" ]
LZO_VERSION=${LZO_VERSION:-2.09}
BLOSC_VERSION=1.10.2

function build_wheel {
    local repo_dir=${1:-$REPO_DIR}
    if [ -z "$IS_OSX" ]; then
        build_linux_wheel $@
    else
        build_osx_wheel $@
    fi
}

function get_cmake {
    local cmake=cmake
    if [ -n "$IS_OSX" ]; then
        brew install cmake > /dev/null
    else
        yum install -y cmake28 > /dev/null
        cmake=cmake28
    fi
    echo $cmake
}

function build_blosc {
    if [ -e blosc-stamp ]; then return; fi
    local cmake=$(get_cmake)
    fetch_unpack https://github.com/Blosc/c-blosc/archive/v${BLOSC_VERSION}.tar.gz
    (cd c-blosc-${BLOSC_VERSION} \
        && $cmake -DCMAKE_INSTALL_PREFIX=$BUILD_PREFIX . \
        && make install)
    touch blosc-stamp
}

function build_libs {
    build_blosc
    build_simple lzo $LZO_VERSION http://www.oberhumer.com/opensource/lzo/download
    build_hdf5
    build_bzip2
}

function build_linux_wheel {
    source multibuild/library_builders.sh
    build_libs
    # Add workaround for auditwheel bug:
    # https://github.com/pypa/auditwheel/issues/29
    local bad_lib="/usr/local/lib/libhdf5.so"
    if [ -z "$(readelf --dynamic $bad_lib | grep RUNPATH)" ]; then
        patchelf --set-rpath $(dirname $bad_lib) $bad_lib
    fi
    build_pip_wheel $@
}

function build_osx_wheel {
    local repo_dir=${1:-$REPO_DIR}
    local wheelhouse=$(abspath ${WHEEL_SDIR:-wheelhouse})
    # Build dual arch wheel
    export CC=clang
    export CXX=clang++
    brew install pkg-config
    # 32-bit wheel
    export CFLAGS="-arch i386"
    export FFLAGS="-arch i386"
    export LDFLAGS="-arch i386"
    # Build libraries
    source multibuild/library_builders.sh
    build_libs
    # Build wheel
    local py_ld_flags="-Wall -undefined dynamic_lookup -bundle"
    local wheelhouse32=${wheelhouse}32
    mkdir -p $wheelhouse32
    export LDFLAGS="$LDFLAGS $py_ld_flags"
    export LDSHARED="clang $LDFLAGS $py_ld_flags"
    build_pip_wheel "$repo_dir"
    mv ${wheelhouse}/*whl $wheelhouse32
    # 64-bit wheel
    export CFLAGS="-arch x86_64"
    export FFLAGS="-arch x86_64"
    export LDFLAGS="-arch x86_64"
    unset LDSHARED
    # Force rebuild of all libs
    rm *-stamp
    build_libs
    # Build wheel
    export LDFLAGS="$LDFLAGS $py_ld_flags"
    export LDSHARED="clang $LDFLAGS $py_ld_flags"
    build_pip_wheel "$repo_dir"
    # Fuse into dual arch wheel(s)
    for whl in ${wheelhouse}/*.whl; do
        delocate-fuse "$whl" "${wheelhouse32}/$(basename $whl)"
    done
}

function run_tests {
    # Runs tests on installed distribution from an empty directory
    python -m tables.tests.test_all
    if [ -n "$IS_OSX" ]; then  # Run 32-bit tests on dual arch wheel
        arch -i386 python -m tables.tests.test_all
    fi
}
