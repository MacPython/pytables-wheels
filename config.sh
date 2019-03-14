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
    build_hdf5
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
    build_pip_wheel "$repo_dir"
}

function run_tests {
    # Runs tests on installed distribution from an empty directory
    python -m tables.tests.test_all
}
