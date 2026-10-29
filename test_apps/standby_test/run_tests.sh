#!/bin/bash
# DRCM node standby tests. Run ./setup.sh start NEW_BINARY [OLD_BINARY]
# first. Prints PASS/FAIL per check and the measured timings, and
# keeps each node's DRCM log in run/NODE/log.
T=$(dirname $(readlink -f $0)); cd $T
EV=$T/shared/events.log
pass=0; fail=0
check() { # description, then a command that must succeed
    local d="$1"; shift
    if "$@"; then echo "PASS $d"; pass=$((pass + 1)); else echo "FAIL $d"; fail=$((fail + 1)); fi
}
not() { ! "$@"; }
mark() { echo "$(date +%s%3N) MARK $1" >> $EV; }
runs() { [ -f $T/shared/state/$2.$1 ]; }   # runs NODE type.name
n1_res="cron.cron1_template ip.10.89.77.100 service.svc1 app.app1 filesystem.fs1"
all_on() { local n=$1; for r in $n1_res; do runs $n $r || return 1; done; }
none_on() { local n=$1; for r in $n1_res; do runs $n $r && return 1; done; return 0; }
wait_for() { # seconds, command
    local s=$1; shift
    while [ $s -gt 0 ]; do "$@" && return 0; sleep 1; s=$((s - 1)); done
    return 1
}
start_drcm() { # node [old]
    local bin=/test/run/drcm_server.new
    [ "$2" == "old" ] && bin=/test/run/drcm_server.old
    podman exec -d -e ASAN_OPTIONS=log_path=/var/log/drcm/asan:detect_leaks=0 \
	-e UBSAN_OPTIONS=print_stacktrace=1:log_path=/var/log/drcm/ubsan $1 \
	bash -c "mkdir -p /var/run/drcm /var/spool/drcm; exec $bin --config-file=/etc/drcm/cm.cfg >> /var/log/drcm/console.log 2>&1" > /dev/null
    sleep 2
}
drcm_running() { podman exec $1 pgrep -f drcm_server > /dev/null 2>&1; }
stop_drcm() {
    podman exec $1 pkill -TERM -f drcm_server > /dev/null 2>&1
    wait_for 120 bash -c "! podman exec $1 pgrep -f drcm_server > /dev/null 2>&1"
}
client() { # node args... (output saved in $T/run/client.out)
    local n=$1; shift
    podman exec $n /test/run/drcm_server.new --client "$@" > $T/run/client.out 2>&1
    local rv=$?
    sed 's/^/    /' $T/run/client.out
    return $rv
}
log_has() { grep -q "$2" $T/run/$1/log/drcm.log; }

: > $EV
for n in n1 n2 n3; do stop_drcm $n; rm -f $T/run/$n/lib/standby $T/run/$n/log/*; done
rm -f $T/shared/state/*

echo "== Start the cluster"
for n in n1 n2 n3; do start_drcm $n; done
check "n1 starts its resources" wait_for 90 all_on n1
check "n2 and n3 start theirs" wait_for 60 bash -c "[ -f shared/state/app.app2.n2 ] && [ -f shared/state/app.app3.n3 ]"

echo "== 1. Standby n1, n2 takes over"
mark standby1; s=$(date +%s%3N)
check "standby command succeeds" client n1 --command=standby
e=$(date +%s%3N); echo "    standby command took $(( (e - s) / 1000 )).$(( (e - s) % 1000 / 100 ))s"
check "n2 runs all of n1's resources" all_on n2
check "n1 runs none of them" none_on n1
check "standby file written" test -f run/n1/lib/standby
check "n3 did not take any" bash -c "! ls shared/state | grep -v app3 | grep -q n3"
check "no overlap during standby" ./analyze.py $EV standby1
stop_order=$(awk '/MARK standby1/{w=1} w && $2=="n1" && $5=="stop" {print $3}' $EV | tr '\n' ' ')
echo "    n1 stop order: $stop_order"
check "IP and file system stopped after the apps" not grep -Eq '(ip|filesystem).*(cron|service|app)' <<< "$stop_order"
check "rstats shows node:standby" bash -c "podman exec n1 /test/run/drcm_server.new --client --command=rstats -nn1 | grep -q '^node:standby,'"
podman exec n1 /test/run/drcm_server.new --client --command=cm_stat > run/cm_stat_standby.txt 2>&1
check "cm_stat shows Standby" grep -q "Standby" run/cm_stat_standby.txt
check "a second standby is accepted as a no-op" client n1 --command=standby

echo "== 2. Restart DRCM on n1 while in standby"
mark restart1
stop_drcm n1; start_drcm n1; sleep 40
check "n1 is still in standby after a DRCM restart" wait_for 10 log_has n1 "Starting in standby"
check "n2 kept the resources" all_on n2
check "n1 did not start any" none_on n1
check "no resource moved during the restart" bash -c "./analyze.py $EV restart1 | grep -c ':' | grep -qx 0"

echo "== 3. Kill the n1 container (reboot) while in standby"
mark reboot1
podman restart -t 0 n1 > /dev/null; start_drcm n1; sleep 40
check "n2 kept the resources after the reboot" all_on n2
check "n1 did not start any after the reboot" none_on n1
check "no resource moved during the reboot" bash -c "./analyze.py $EV reboot1 | grep -c ':' | grep -qx 0"

echo "== 4. Unstandby n1, resources fail back"
mark unstandby1; s=$(date +%s%3N)
check "unstandby command succeeds" client n1 --command=unstandby
e=$(date +%s%3N); echo "    unstandby command took $(( (e - s) / 1000 )).$(( (e - s) % 1000 / 100 ))s"
check "n1 runs its resources again" all_on n1
check "n2 stopped its backup copies" wait_for 10 none_on n2
check "standby file removed" test ! -f run/n1/lib/standby
check "no overlap during fail back" ./analyze.py $EV unstandby1
./analyze.py $EV unstandby1 | grep gap

echo "== 5. Request from another host is rejected"
# A client on n2 whose config gives n2 the keep alive address of n1, so
# its request for n2 goes to n1's server from n2's address
podman exec n2 bash -c "sed 's/= 10.89.77.12$/= 10.89.77.11/' /etc/drcm/cm.cfg > /tmp/remote.cfg"
podman exec n2 /test/run/drcm_server.new --client --config-file=/tmp/remote.cfg --command=standby --force > run/client.out 2>&1
sed 's/^/    /' run/client.out
check "n1 rejected the remote request" wait_for 10 log_has n1 "Rejected standby request from 10.89.77.12"
check "the client reports the rejection" grep -q "only accepted from this host" run/client.out
check "n1 is not in standby" all_on n1
check "n2 is not in standby" test ! -f run/n2/lib/standby

echo "== 6. Refuse standby with no peer to take over, then --force"
stop_drcm n2; stop_drcm n3
mark refuse1
check "standby is refused with no peer" not client n1 --command=standby
check "n1 kept its resources" all_on n1
check "no standby file after a refusal" test ! -f run/n1/lib/standby
echo "    waiting for n1 to take over app2 and app3 from the stopped peers"
check "n1 took over app2 and app3" wait_for 120 bash -c "[ -f shared/state/app.app2.n1 ] && [ -f shared/state/app.app3.n1 ]"
check "standby --force succeeds" client n1 --command=standby --force
check "n1 stopped its own resources" none_on n1
check "n1 stopped the app2 and app3 backups" bash -c "[ ! -f shared/state/app.app2.n1 ] && [ ! -f shared/state/app.app3.n1 ]"
check "unstandby with the peers down" client n1 --command=unstandby
check "n1 takes back its own and the backups" wait_for 60 bash -c "[ -f shared/state/app.app2.n1 ] && [ -f shared/state/app.app3.n1 ]"
start_drcm n2; start_drcm n3
check "app2 and app3 fail back to n2 and n3" wait_for 120 bash -c "[ -f shared/state/app.app2.n2 ] && [ -f shared/state/app.app3.n3 ] && [ ! -f shared/state/app.app2.n1 ]"

if [ -x run/drcm_server.old ]; then
    echo "== 7. Mixed versions, n2 runs the old drcm_server"
    stop_drcm n2; start_drcm n2 old
    check "app2 back on old n2" wait_for 90 test -f shared/state/app.app2.n2
    mark mixed1
    check "standby is refused when only an old peer backs up n1" not client n1 --command=standby
    grep -q "no standby support" run/client.out && echo "    (n2 reported as an old version)"
    check "standby --force with an old peer" client n1 --command=standby --force
    sleep 30
    check "old n2 did not take over (no split brain)" none_on n2
    check "n1 runs none of its resources" none_on n1
    check "old n2 still sees n1 alive" bash -c "! grep -q 'n1 is dead' run/n2/log/drcm.log"
    check "unstandby with an old peer" client n1 --command=unstandby
    check "n1 runs its resources again" all_on n1
    check "no overlap in the mixed test" ./analyze.py $EV mixed1
    stop_drcm n2; start_drcm n2
fi

echo "== Stop the cluster"
for n in n1 n2 n3; do stop_drcm $n; done
for n in n1 n2 n3; do
    if ls run/$n/log/asan* run/$n/log/ubsan* > /dev/null 2>&1; then
	echo "Sanitizer reports on $n:"; ls run/$n/log/asan* run/$n/log/ubsan* 2>/dev/null
	fail=$((fail + 1))
    fi
done
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
