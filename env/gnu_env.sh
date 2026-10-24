#!/bin/bash
# source this script to setup compiler ENV

export BUILD="gnu"
export COMPILER="gnu"

echo "Using GCC and G++ compilers for all binary builds"

export CC="gcc"
export CXX="g++"
export CPP="${CC} -E"

# Build with optimization, warnings, and runtime hardening. The
# hardening flags (stack protector, fortified libc calls, read-only
# relocations and a position independent executable) add exploit
# mitigation at little cost and are the modern distro defaults.
HARDEN_CFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE"
HARDEN_LDFLAGS="-Wl,-z,relro,-z,now -pie"

export CFLAGS="-O2 -Wall ${HARDEN_CFLAGS}"
export CXXFLAGS="-O2 -Wall ${HARDEN_CFLAGS}"
export LDFLAGS="${HARDEN_LDFLAGS}"

export NUMCPUS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc)
