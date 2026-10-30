#!/bin/bash
# Builds a three node DRCM test cluster in rootless podman for
# run_tests.sh: n1, n2 and n3 on network drcmsbnet (10.89.77.0/24),
# UDP keep alives, fake resources (res.sh) that log every start and
# stop to shared/events.log.
#
# Usage: [TRANSPORT=tcp] ./setup.sh start NEW_BINARY [OLD_BINARY [PREV_BINARY [PREV146_BINARY]]]
#        ./setup.sh stop
# NEW_BINARY is the drcm_server under test (an AddressSanitizer build
# works too). OLD_BINARY, if given, is a 1.42 drcm_server for the
# mixed version test. PREV_BINARY, if given, is a 1.44 drcm_server
# for the test that an older server refuses a timed standby, and
# PREV146_BINARY a 1.46 drcm_server for the test that it refuses a
# remote standby. TRANSPORT=tcp runs the cluster over TCP + TLS with a
# test CA and pinned node certificates (tls_peer_fingerprint).
# x4 and x2 are client-only containers for the remote standby tests:
# x4 is a host that is not in the CM config, x2 claims hostname n2 but
# has its own certificate.
set -e
T=$(dirname $(readlink -f $0)); cd $T
NODES="n1 n2 n3"
CLIENTS="x4 x2"
TRANSPORT=${TRANSPORT:-udp}
if [ "$1" == "stop" ]; then
    for n in $NODES $CLIENTS; do podman rm -f -t 2 $n > /dev/null 2>&1 || true; done
    podman network rm drcmsbnet > /dev/null 2>&1 || true
    exit 0
fi
if [ "$1" != "start" ] || [ ! -x "$2" ]; then
    echo "Usage: $0 start NEW_BINARY [OLD_BINARY [PREV_BINARY]] | stop"; exit 1
fi
NEW=$(readlink -f $2)
OLD=""; if [ -n "$3" ]; then OLD=$(readlink -f $3); fi
PREV=""; if [ -n "$4" ]; then PREV=$(readlink -f $4); fi
PREV146=""; if [ -n "$5" ]; then PREV146=$(readlink -f $5); fi

podman build -q -t drcmsbtest . > /dev/null
rm -rf run shared; mkdir -p run/etc/.auth shared/state
cp $NEW run/drcm_server.new
if [ -n "$OLD" ]; then cp $OLD run/drcm_server.old; fi
if [ -n "$PREV" ]; then cp $PREV run/drcm_server.prev; fi
if [ -n "$PREV146" ]; then cp $PREV146 run/drcm_server.prev146; fi
echo $TRANSPORT > run/transport
dd if=/dev/urandom bs=1024 count=2 of=run/etc/.auth/authkey status=none
sha1sum run/etc/.auth/authkey | cut -b1-40 > run/etc/.auth/authkey.sha1
chmod 700 run/etc/.auth; chmod 600 run/etc/.auth/*
touch run/cron1_template

# TCP mode: a test CA and one certificate per node and client container
fp() { openssl x509 -in run/tls/$1/node.crt -noout -fingerprint -sha256 | cut -d= -f2; }
if [ "$TRANSPORT" == "tcp" ]; then
    mkdir -p run/tls
    openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=drcm test CA" \
	-keyout run/tls/ca.key -out run/tls/ca.crt 2> /dev/null
    for n in $NODES $CLIENTS; do
	mkdir -p run/tls/$n
	openssl req -newkey rsa:2048 -nodes -subj "/CN=$n" -keyout run/tls/$n/node.key \
	    -out run/tls/$n/node.csr 2> /dev/null
	openssl x509 -req -in run/tls/$n/node.csr -CA run/tls/ca.crt -CAkey run/tls/ca.key \
	    -CAcreateserial -days 2 -out run/tls/$n/node.crt 2> /dev/null
	cp run/tls/ca.crt run/tls/$n/ca.crt
	chmod 700 run/tls/$n; chmod 600 run/tls/$n/node.key
    done
fi

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
$( [ "$TRANSPORT" == "tcp" ] && echo "tls_peer_fingerprint = $(fp $1)" )
$3
$4
END
}
{
cat <<END
[CM_SERVER]
udpport = 53897
$( [ "$TRANSPORT" == "tcp" ] && printf 'cluster_transport = tcp\ntls_ca_file = /etc/drcm/tls/ca.crt\ntls_cert_file = /etc/drcm/tls/node.crt\ntls_key_file = /etc/drcm/tls/node.key\ntls_min_version = 1.3\n' )
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
node n1 1 "allow_remote_standby = 1
node_crontabs = cron1
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

# The client-only containers get their own copy of /etc/drcm, so a test
# can give x4 a wrong auth key
for c in $CLIENTS; do cp -a run/etc run/etc_$c; mkdir -p run/$c/log; done

podman network create --subnet 10.89.77.0/24 drcmsbnet > /dev/null 2>&1 || true
start_container() { # name hostname ip etcdir
    local tlsmount=""
    [ "$TRANSPORT" == "tcp" ] && tlsmount="-v $T/run/tls/$1:/etc/drcm/tls:z"
    podman rm -f -t 2 $1 > /dev/null 2>&1 || true
    mkdir -p run/$1/log run/$1/lib
    podman run -d --name $1 --hostname $2 --network drcmsbnet --ip $3 \
	-v $T:/test:ro,z -v $T/shared:/shared:z -v $T/run/$4:/etc/drcm:z $tlsmount \
	-v $T/run/$1/log:/var/log/drcm:z -v $T/run/$1/lib:/var/lib/drcm:z \
	drcmsbtest sleep infinity > /dev/null
}
i=1
for n in $NODES; do start_container $n $n 10.89.77.1$i etc; i=$((i + 1)); done
start_container x4 n4 10.89.77.14 etc_x4
start_container x2 n2 10.89.77.15 etc_x2
echo "Test nodes $NODES and clients $CLIENTS are up ($TRANSPORT), run ./run_tests.sh"
