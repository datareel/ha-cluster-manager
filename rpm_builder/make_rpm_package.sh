umask 0022

if [ -z $USERNAME ]; then USERNAME=$(whoami); fi
BUILDDIR_tmp="/tmp/drcm_build_${USERNAME}"

if [ -z $1 ]; then
    echo "You must supply a OS version"
    echo "Usage: ${0} rhel8|rhel8-openssl35|rhel9|rhel10"
    exit 1
fi

OS=${1,,}

# rhel8-openssl35 (1.49): the RHEL 8 package drcm_server-openssl35, built from
# drcm_rhel8.spec with OpenSSL 3.5 linked in statically (post-quantum TLS).
# It provides drcm_server and conflicts with it; switch with
# "dnf install --allowerasing ./drcm_server-openssl35-*.rpm", or dnf swap
# from a repository (stop DRCM first).
FLAVOR=system
SPEC_OS=${OS}
if [ "${OS}" == "rhel8-openssl35" ]; then
    FLAVOR=openssl35
    SPEC_OS=rhel8
    OPENSSL35_PREFIX=${OPENSSL35_PREFIX:-/opt/openssl-3.5}
    if [ ! -f "${OPENSSL35_PREFIX}/lib64/libssl.a" ]; then
        echo "ERROR - No static OpenSSL 3.5 in ${OPENSSL35_PREFIX}; run build/build_openssl35.sh first"
        exit 1
    fi
fi

if [ ! -z "${2}" ]; then BUILDDIR_tmp="${2}"; fi
 
mkdir -p ${BUILDDIR_tmp}/rpmbuild/BUILD
mkdir -p ${BUILDDIR_tmp}/rpmbuild/BUILDROOT
mkdir -p ${BUILDDIR_tmp}/rpmbuild/RPMS
mkdir -p ${BUILDDIR_tmp}/rpmbuild/SOURCES
mkdir -p ${BUILDDIR_tmp}/rpmbuild/SPECS
mkdir -p ${BUILDDIR_tmp}/rpmbuild/SRPMS

mkdir -p ${HOME}/rpmbuild/BUILD
mkdir -p ${HOME}/rpmbuild/BUILDROOT
mkdir -p ${HOME}/rpmbuild/RPMS
mkdir -p ${HOME}/rpmbuild/SOURCES
mkdir -p ${HOME}/rpmbuild/SPECS
mkdir -p ${HOME}/rpmbuild/SRPMS

if [ ! -d ${BUILDDIR_tmp}/rpmbuild/BUILDROOT ]; then
    echo "ERROR - Cannot create BUILDROOT: ${BUILDDIR_tmp}/rpmbuild/BUILDROOT"
    exit 1
fi

if [ ! -d ${BUILDDIR_tmp}/rpmbuild/SPECS ]; then
    echo "ERROR - Cannot create SPECS dir: ${BUILDDIR_tmp}/rpmbuild/SPECS"
    exit 1
fi

cp -fv drcm_${SPEC_OS}.spec ${BUILDDIR_tmp}/rpmbuild/SPECS/drcm.spec
if [ "${FLAVOR}" == "openssl35" ]; then
    # Provides/Conflicts go after Release:, where %{version} and %{release} are defined
    sed -i -e 's/^Name: drcm_server$/Name: drcm_server-openssl35/' \
           -e 's/^\(Release: .*\)$/\1\nProvides: drcm_server = %{version}-%{release}\nConflicts: drcm_server/' \
           -e 's/^Summary: .*/Summary: Datareel Cluster Manager RPM, OpenSSL 3.5 static build (post-quantum TLS)/' \
           ${BUILDDIR_tmp}/rpmbuild/SPECS/drcm.spec
    grep -q '^Name: drcm_server-openssl35' ${BUILDDIR_tmp}/rpmbuild/SPECS/drcm.spec || { echo "ERROR - spec Name not changed"; exit 1; }
fi
Version=$(head -15 ${BUILDDIR_tmp}/rpmbuild/SPECS/drcm.spec | grep 'Version:' | awk -F: '{ print $2 }')
Version=$( echo "${Version}" | sed s/' '//g)
Release=$(head -15 ${BUILDDIR_tmp}/rpmbuild/SPECS/drcm.spec | grep 'Release:' | awk -F: '{ print $2 }')
Release=$( echo "${Release}" | sed s/' '//g)

Build="${BUILDDIR_tmp}/rpmbuild/BUILD/drcm_server"
mkdir -pv "${Build}"

if [ ! -d "${Build}" ]; then
    echo "ERROR - Cannot make Build: ${Build}"
    exit 1;
fi

source ../../env/gnu_env.sh
cd ../drcm_server

# OpenSSL per package (1.49):
#   rhel8            system OpenSSL 1.1.1 (FIPS-validated by Red Hat, classic TLS)
#   rhel8-openssl35  static OpenSSL 3.5 (build/build_openssl35.sh), post-quantum TLS
#   rhel9, rhel10    system OpenSSL 3.5
OSSL_ARGS=""
if [ "${FLAVOR}" == "openssl35" ]; then
    OSSL_ARGS="OPENSSL_PREFIX=${OPENSSL35_PREFIX} OPENSSL_STATIC=1"
fi
make clean_lib
make clean
make ${OSSL_ARGS}

if [ ! -x drcm_server ]; then
    echo "ERROR - drcm_server was not built"
    exit 1
fi
LINKED=$(./drcm_server --version | grep '^Linked with:')
OSSL_VER=$(echo "${LINKED}" | sed -n 's/^Linked with: OpenSSL \([0-9][0-9.]*\).*/\1/p')
echo "drcm_server ${LINKED}"
case "${OS}" in
    rhel8)
        readelf -d drcm_server | grep -q 'libssl.so.1.1' || { echo "ERROR - the rhel8 package must link the system OpenSSL 1.1.1"; exit 1; }
        echo "${LINKED}" | grep -q ', system ' || { echo "ERROR - not a system OpenSSL build"; exit 1; } ;;
    rhel8-openssl35)
        if readelf -d drcm_server | grep -q 'NEEDED.*lib\(ssl\|crypto\)'; then
            echo "ERROR - the openssl35 package must not link a shared libssl/libcrypto"; exit 1
        fi
        echo "${LINKED}" | grep -q ', static ' || { echo "ERROR - not a static OpenSSL build"; exit 1; }
        case "${OSSL_VER}" in 3.5.*) ;; *) echo "ERROR - OpenSSL ${OSSL_VER}, 3.5 required"; exit 1 ;; esac ;;
    *)
        if readelf -d drcm_server | grep -q 'libssl.so.1'; then
            echo "ERROR - drcm_server links OpenSSL 1.x"; exit 1
        fi
        case "${OSSL_VER}" in
            3.[5-9]*|3.[1-9][0-9]*|[4-9].*) ;;
            *) echo "ERROR - OpenSSL '${OSSL_VER}', 3.5 or later is required"; exit 1 ;;
        esac ;;
esac

mkdir -p ${Build}/etc/drcm
chmod 755 ${Build}/etc/drcm
cp -fv ../etc/cm_2_node_example.cfg ${Build}/etc/drcm/.
chmod 644 ${Build}/etc/drcm/cm_2_node_example.cfg
cp -fv ../etc/cm_4_node_example.cfg ${Build}/etc/drcm/.
chmod 644 ${Build}/etc/drcm/cm_4_node_example.cfg
mkdir -p ${Build}/etc/drcm/file_system_sync
chmod 755 ${Build}/etc/drcm/file_system_sync
cp -fv ../etc/file_system_sync/* ${Build}/etc/drcm/file_system_sync/.
chmod 755 ${Build}/etc/drcm/file_system_sync/*
mkdir -p ${Build}/etc/drcm/utils
mkdir -pv ${Build}/etc/drcm/utils
chmod 755 ${Build}/etc/drcm/utils
cp -fv ../etc/utils/* ${Build}/etc/drcm/utils/.
chmod 755  ${Build}/etc/drcm/utils/*
mkdir -p ${Build}/etc/drcm/my_cluster_conf
chmod 755 ${Build}/etc/drcm/my_cluster_conf
cp -fv ../etc/my_cluster_conf/my_cluster_info.sh ${Build}/etc/drcm/my_cluster_conf/my_cluster_info.sh
chmod 755 ${Build}/etc/drcm/my_cluster_conf/my_cluster_info.sh
cp -fv ../etc/my_cluster_conf/my_cluster_info_example1.sh ${Build}/etc/drcm/my_cluster_conf/.
chmod 644 ${Build}/etc/drcm/my_cluster_conf/my_cluster_info_example1.sh
cp -fv ../etc/my_cluster_conf/testfs_sync_list.sh ${Build}/etc/drcm/my_cluster_conf/.
chmod 644 ${Build}/etc/drcm/my_cluster_conf/testfs_sync_list.sh
mkdir -p ${Build}/etc/drcm/resources
chmod 755 ${Build}/etc/drcm/resources
cp -fv ../etc/resources/* ${Build}/etc/drcm/resources/.
chmod 755 ${Build}/etc/drcm/resources/*
mkdir -p ${Build}/etc/drcm/crontabs
cp -fv ../etc/crontabs/apps_package1 ${Build}/etc/drcm/crontabs/apps_package1
cp -fv ../etc/crontabs/apps_package2 ${Build}/etc/drcm/crontabs/apps_package2
cp -fv ../etc/crontabs/apps_package3 ${Build}/etc/drcm/crontabs/apps_package3
cp -fv ../etc/crontabs/apps_package4 ${Build}/etc/drcm/crontabs/apps_package4
cp -fv ../etc/crontabs/system_crons ${Build}/etc/drcm/crontabs/system_crons
cp -fv ../etc/crontabs/user_crons ${Build}/etc/drcm/crontabs/user_crons
chmod 644 ${Build}/etc/drcm/crontabs/*
mkdir -p ${Build}/etc/drcm/.auth/
chmod 700 ${Build}/etc/drcm/.auth/
mkdir -p ${Build}/var/log/drcm
chmod 755 ${Build}/var/log/drcm
mkdir -p ${Build}/var/spool/drcm
chmod 755 ${Build}/var/spool/drcm
mkdir -p ${Build}/var/run/drcm
chmod 755 ${Build}/var/run/drcm
mkdir -p ${Build}/var/lib/drcm
chmod 755 ${Build}/var/lib/drcm
mkdir -p ${Build}/usr/sbin
chmod 755 ${Build}/usr/sbin
cp -fv drcm_server ${Build}/usr/sbin/drcm_server
chmod 755 ${Build}/usr/sbin/drcm_server
# All supported targets (RHEL 8, 9, 10) use the native systemd unit
# installed below; no SysV init script is shipped.
mkdir -p ${Build}/etc/sysconfig
chmod 755 ${Build}/etc/sysconfig
cp -fv ../etc/system_templates/drcm_server_sysconfig ${Build}/etc/sysconfig/drcm_server
chmod 644 ${Build}/etc/sysconfig/drcm_server
mkdir -p ${Build}/usr/share/doc/drcm
chmod 755 ${Build}/usr/share/doc/drcm
cp -fv ../README.txt ${Build}/usr/share/doc/drcm/README.txt
chmod 644 ${Build}/usr/share/doc/drcm/README.txt
cp -fv ../COPYING ${Build}/usr/share/doc/drcm/COPYING
chmod 644 ${Build}/usr/share/doc/drcm/COPYING
cp -fv ../version.txt ${Build}/usr/share/doc/drcm/version.txt
chmod 644 ${Build}/usr/share/doc/drcm/version.txt
# Administrator guide, white paper, release notes and the AI-assisted guide
# files (1.49). The same files are on datareel.com/drcm/.
for f in docs/drcm.html docs/drcm.txt docs/drcm_white_paper.html docs/drcm_white_paper.txt \
         CHANGELOG.md AGENTS.md GEMINI.md CLAUDE.md tools/drcm_preflight.sh; do
    if [ ! -f ../${f} ]; then
        echo "ERROR - Missing doc file ${f}"
        exit 1
    fi
    cp -fv ../${f} ${Build}/usr/share/doc/drcm/$(basename ${f})
    chmod 644 ${Build}/usr/share/doc/drcm/$(basename ${f})
done
mkdir -p ${Build}/usr/share/man/man1
mkdir -p ${Build}/usr/share/man/man8
gzip -c ../man/drcm_server.1 > ${Build}/usr/share/man/man1/drcm_server.1.gz
gzip -c ../man/drcm_server.8 > ${Build}/usr/share/man/man8/drcm_server.8.gz
chmod 644  ${Build}/usr/share/man/man1/drcm_server.1.gz
chmod 644 ${Build}/usr/share/man/man8/drcm_server.8.gz
if [ "${SPEC_OS}" == "rhel8" ] || [ "${SPEC_OS}" == "rhel9" ] || [ "${SPEC_OS}" == "rhel10" ]; then
    mkdir -p ${Build}/usr/lib/systemd/system
    chmod 755 ${Build}/usr/lib/systemd/system
    cp -fv ../systemd_init/drcm_server.service  ${Build}/usr/lib/systemd/system/drcm_server.service
    chmod 644 ${Build}/usr/lib/systemd/system/drcm_server.service
fi

cd ${Build}
if [ -f ${HOME}/rpmbuild/BUILD/drcm_server.tar.gz ]; then
    rm -f ${HOME}/rpmbuild/BUILD/drcm_server.tar.gz
fi
tar cfz ${HOME}/rpmbuild/BUILD/drcm_server.tar.gz *

cd ${BUILDDIR_tmp}/rpmbuild/SPECS
# A fixed build host name, so the build machine's own host name never goes
# into the RPM header (rpm -qi shows Build Host)
rpmbuild -ba --define "_buildhost build.datareel.com" --buildroot=${BUILDDIR_tmp}/rpmbuild/BUILDROOT drcm.spec

rm -f ${HOME}/rpmbuild/BUILD/drcm_server.tar.gz
rm -rf ${BUILDDIR_tmp}

