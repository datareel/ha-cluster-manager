#!/bin/bash
# vg_session.sh - one DRCM node (n1) under valgrind for a short session (final 6.4 test, not part of the suite)
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
    [ "$2" == "prev" ] && bin=/test/run/drcm_server.prev
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
podman cp /usr/bin/valgrind n1:/usr/bin/valgrind && podman cp /usr/libexec/valgrind n1:/usr/libexec/
podman exec -d n1 bash -c "mkdir -p /var/run/drcm /var/spool/drcm; exec valgrind --log-file=/var/log/drcm/valgrind.log --error-limit=no --leak-check=no --track-fds=no /test/run/drcm_server.new --config-file=/etc/drcm/cm.cfg >> /var/log/drcm/console.log 2>&1"
sleep 5
for n in n2 n3; do start_drcm $n; done
check "n1 (under valgrind) starts its resources" wait_for 300 all_on n1
mark vg1
client n2 --command=status > /dev/null
podman exec n1 /test/run/drcm_server.new --client --command=standby > /dev/null 2>&1
check "standby: n2 takes everything" wait_for 300 all_on n2
podman exec n1 /test/run/drcm_server.new --client --command=unstandby > /dev/null 2>&1
check "unstandby: everything back on n1" wait_for 400 all_on n1
check "no overlap" ./analyze.py $EV vg1
stop_drcm n1
grep -E 'ERROR SUMMARY|Invalid (read|write)|uninitialised|Conditional jump' $T/run/n1/log/valgrind.log | sort | uniq -c | head -12
check "valgrind: 0 errors" grep -q 'ERROR SUMMARY: 0 errors' $T/run/n1/log/valgrind.log
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
