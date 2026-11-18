#!/bin/bash
# Build the static OpenSSL 3.5 LTS library for the RHEL 8 drcm_server-openssl35
# package (1.49). RHEL 8's system OpenSSL is 1.1.1, which has no post-quantum
# TLS key exchange; this links OpenSSL 3.5 into drcm_server instead.
#
#   build/build_openssl35.sh [PREFIX]        default PREFIX: /opt/openssl-3.5
#   RUN_TESTS=1 build/build_openssl35.sh ... also runs OpenSSL's test suite
#
# The tarball is downloaded from the OpenSSL project on GitHub and must match
# the pinned SHA-256 below (published at openssl.org/source as well);
# anything else stops the build. To move to a newer 3.5.x release, change
# OSSL_VERSION and OSSL_SHA256 together, from the openssl.org .sha256 file.
#
# Needs: gcc, make, perl, perl-IPC-Cmd, perl-Time-Piece, curl.
# Then build the RPM with: bash rpm_builder/make_rpm_package.sh rhel8-openssl35
# (make_rpm_package.sh uses OPENSSL35_PREFIX, default /opt/openssl-3.5).

set -eu
OSSL_VERSION=3.5.9
OSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
PREFIX=${1:-/opt/openssl-3.5}
WORK=${WORK:-$(mktemp -d /tmp/openssl35_build.XXXXXX)}
TARBALL=openssl-${OSSL_VERSION}.tar.gz
URL=https://github.com/openssl/openssl/releases/download/openssl-${OSSL_VERSION}/${TARBALL}

cd "${WORK}"
if [ ! -f "${TARBALL}" ]; then
    echo "Downloading ${URL}"
    curl -sSfLO "${URL}"
fi
GOT=$(sha256sum "${TARBALL}" | cut -c1-64)
if [ "${GOT}" != "${OSSL_SHA256}" ]; then
    echo "ERROR - ${TARBALL} sha256 ${GOT} does not match the pinned ${OSSL_SHA256}"
    exit 1
fi
echo "${TARBALL} sha256 OK"

rm -rf "openssl-${OSSL_VERSION}"
tar xzf "${TARBALL}"
cd "openssl-${OSSL_VERSION}"
# no-shared: static libssl.a and libcrypto.a only, nothing to install on
# the cluster nodes. enable-fips also builds the (not yet validated) 3.5
# FIPS provider module, kept with the library for reference.
./Configure linux-x86_64 no-shared enable-fips --prefix="${PREFIX}" --openssldir="${PREFIX}/ssl"
make -j"$(nproc)"
if [ "${RUN_TESTS:-0}" == "1" ]; then
    make -j"$(nproc)" test
fi
make install_sw install_fips
echo "OpenSSL ${OSSL_VERSION} installed in ${PREFIX}:"
ls -l "${PREFIX}"/lib64/libssl.a "${PREFIX}"/lib64/libcrypto.a
"${PREFIX}/bin/openssl" version
