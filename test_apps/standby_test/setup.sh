#!/bin/bash
# Builds a three node DRCM test cluster in rootless podman for
# run_tests.sh: n1, n2 and n3 on network drcmsbnet (10.89.77.0/24),
# UDP keep alives, fake resources (res.sh) that log every start and
# stop to shared/events.log.
#
# Usage: ./setup.sh start NEW_BINARY [OLD_BINARY]
#        ./setup.sh stop
# NEW_BINARY is the drcm_server under test (an AddressSanitizer build
# works too). OLD_BINARY, if given, is a 1.42 drcm_server for the
# mixed version test.
set -e
T=$(dirname $(readlink -f $0)); cd $T
NODES="n1 n2 n3"
if [ "$1" == "stop" ]; then
    for n in $NODES; do podman rm -f -t 2 $n > /dev/null 2>&1 || true; done
    podman network rm drcmsbnet > /dev/null 2>&1 || true
    exit 0
fi
if [ "$1" != "start" ] || [ ! -x "$2" ]; then
    echo "Usage: $0 start NEW_BINARY [OLD_BINARY] | stop"; exit 1
fi
NEW=$(readlink -f $2)
OLD=""; if [ -n "$3" ]; then OLD=$(readlink -f $3); fi

podman build -q -t drcmsbtest . > /dev/null
rm -rf run shared; mkdir -p run/etc/.auth shared/state
cp $NEW run/drcm_server.new
if [ -n "$OLD" ]; then cp $OLD run/drcm_server.old; fi
dd if=/dev/urandom bs=1024 count=2 of=run/etc/.auth/authkey status=none
sha1sum run/etc/.auth/authkey | cut -b1-40 > run/etc/.auth/authkey.sha1
chmod 700 run/etc/.auth; chmod 600 run/etc/.auth/*
touch run/cron1_template

node() { # nodename index own_resources backup_resources
    cat <<END
[CM_NODE]
nodename = $1
hostname = $1
node_is_active = 1
keep_services = 0
keep_filesystems = 0
keep_applications = 0
keep_alive_ip = 10.89.77.1$2
ipaddrs_check = $((10 + $2))
filesystems_check = $((11 + $2))
services_check = $((12 + $2))
crontabs_check = $((13 + $2))
applications_check = $((14 + $2))
$3
$4
END
}
{
cat <<END
[CM_SERVER]
udpport = 53897
tcpport = 53897
dead_node_count = 10
run_dir = /var/run/drcm
log_dir = /var/log/drcm
spool_dir = /var/spool/drcm
cluster_user = root
cluster_group = root
bash_shell = /bin/bash
logfile = drcm.log
log_level = 5
enable_logging = 1
debug = 0
verbose = 0

[CM_CRONTABS]
cron1, /test/run/cron1_template, /tmp, /test/res_cron.sh

[CM_IPADDRS]
vip1, 10.89.77.100, 24, eth0, /test/res_ip.sh

[CM_SERVICES]
svc1, svc1, /test/res_service.sh

[CM_APPLICATIONS]
app1, root:root, /test/res.sh app app1 start, /test/res.sh app app1 stop, /test/res.sh app app1 ensure
app2, root:root, /test/res.sh app app2 start, /test/res.sh app app2 stop, /test/res.sh app app2 ensure
app3, root:root, /test/res.sh app app3 start, /test/res.sh app app3 stop, /test/res.sh app app3 ensure

[CM_FILESYSTEMS]
fs1, server:/fs1, /mnt/fs1, /test/res_fs.sh

END
node n1 1 "node_crontabs = cron1
node_floating_ip_addrs = vip1
node_services = svc1
node_applications = app1
node_filesystems = fs1" "node_backup_applications = n2:app2, n3:app3"
echo
node n2 2 "node_applications = app2" "node_backup_crontabs = n1:cron1
node_backup_floating_ip_addrs = n1:vip1
node_backup_services = n1:svc1
node_backup_applications = n1:app1
node_backup_filesystems = n1:fs1"
echo
node n3 3 "node_applications = app3" ""
} > run/etc/cm.cfg

podman network create --subnet 10.89.77.0/24 drcmsbnet > /dev/null 2>&1 || true
i=1
for n in $NODES; do
    mkdir -p run/$n/log run/$n/lib
    podman rm -f -t 2 $n > /dev/null 2>&1 || true
    podman run -d --name $n --hostname $n --network drcmsbnet --ip 10.89.77.1$i \
	-v $T:/test:ro,z -v $T/shared:/shared:z -v $T/run/etc:/etc/drcm:z \
	-v $T/run/$n/log:/var/log/drcm:z -v $T/run/$n/lib:/var/lib/drcm:z \
	drcmsbtest sleep infinity > /dev/null
    i=$((i + 1))
done
echo "Test nodes $NODES are up, run ./run_tests.sh"
