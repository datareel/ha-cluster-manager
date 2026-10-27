#!/bin/bash
# Builds two test nodes, "ws" (primary) and "aws" (backup), for
# run_tests.sh. Rootless podman with only uid 0 mapped cannot run sshd,
# so fakessh.py stands in for ssh/sshd and fake_drcm for drcm_server.
# "hg" is a third node with no DRCM, for the 3-way sync tests.
# Usage: ./setup.sh [start|stop]
set -e
T=$(dirname $(readlink -f $0)); cd $T
REPO=$(readlink -f $T/../..)
if [ "$1" == "stop" ]; then
    podman rm -f ws aws hg > /dev/null 2>&1 || true
    podman network rm drcmfsnet > /dev/null 2>&1 || true
    rm -rf $T/shared $T/drcm_etc
    exit 0
fi
podman build -q -t drcmfstest . > /dev/null
rm -rf shared drcm_etc; mkdir -p shared
cp -a $REPO/etc drcm_etc
cat > drcm_etc/my_cluster_conf/my_cluster_info.sh <<'END'
export CLUSTER_NAME="TEST"
export BACKUP_USER="root"
export PRIMARY_FILESYSTEMS_HOST="ws"
export BACKUP_FILESYSTEMS_HOST="aws"
export PRIMARY_FILESYSTEMS_IP="drcm-ws"
export BACKUP_FILESYSTEMS_IP="drcm-aws"
export PRIMARY_FILESYSTEMS_KEEPALIVE_IP="127.0.0.1"
export BACKUP_FILESYSTEMS_KEEPALIVE_IP="127.0.0.2"
export NODE_UP_CHECK="ssh"
export LOGdir=/root/drcmlog
export TERTIARY_FILESYSTEMS_IP="drcm-hg"
export TERTIARY_FILESYSTEMS_DIR="/backup"
END
cat > drcm_etc/my_cluster_conf/osa_sync_list.sh <<'END'
RsyncExclude "/logs/"
RsyncExclude "/proc/"
RsyncExclude "*.lock"
RsyncExclude ".*.lock"
RsyncMirror /root/osa_data
END
printf '#!/bin/bash\nexport SERVICENAME=osa\n. /etc/drcm/file_system_sync/sync_file_system_include.sh\n' > drcm_etc/file_system_sync/sync_osa.sh
chmod 755 drcm_etc/file_system_sync/sync_osa.sh
echo "* * * * * root echo test" > drcm_etc/crontabs/osa_crons
echo "ws=up aws=up" > shared/state
podman network create drcmfsnet > /dev/null 2>&1 || true
for n in ws aws hg; do
    podman rm -f $n > /dev/null 2>&1 || true
    podman run -d --name $n --hostname $n --network drcmfsnet \
	-v $T/shared:/shared:z -v $T/drcm_etc:/drcm_etc:ro,z \
	-v $T/fake_drcm:/fake_drcm:ro,z -v $T/node_init.sh:/node_init.sh:ro,z \
	-v $T/fakessh.py:/fakessh.py:ro,z -v $T/fakescp:/fakescp:ro,z \
	drcmfstest /node_init.sh > /dev/null
done
sleep 2
echo "Test nodes ws, aws and hg are up, run ./run_tests.sh"
