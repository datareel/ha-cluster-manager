#!/bin/bash
# soak.sh [SECONDS] - repeated standby/unstandby failover cycles (default 600 s); every cycle must hand all of n1's resources to n2 and back with no overlap. Run ./setup.sh start NEW_BINARY first.
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

DUR=${1:-600}
: > $EV
for n in n1 n2 n3; do stop_drcm $n; rm -f $T/run/$n/lib/standby $T/run/$n/log/*; done
rm -f $T/shared/state/*
for n in n1 n2 n3; do start_drcm $n; done
check "cluster up" wait_for 90 all_on n1
end=$(( $(date +%s) + DUR )); c=0
while [ $(date +%s) -lt $end ]; do
  c=$((c + 1)); mark cyc$c
  client n1 --command=standby > /dev/null
  check "cycle $c: n2 holds everything" wait_for 120 bash -c "$(declare -f runs all_on); T=$T; n1_res='$n1_res'; all_on n2"
  check "cycle $c: n1 holds nothing" none_on n1
  client n1 --command=unstandby > /dev/null
  check "cycle $c: everything back on n1" wait_for 240 all_on n1
  check "cycle $c: no overlap" ./analyze.py $EV cyc$c
  if [ $((c % 4)) -eq 0 ]; then stop_drcm n3; start_drcm n3; check "cycle $c: n3 restart moved nothing" all_on n1; fi
done
for n in n1 n2 n3; do
  check "no sanitizer report on $n" bash -c "! ls $T/run/$n/log/ | grep -qE '^(asan|ubsan)'"
  check "$n DRCM still running" drcm_running $n
done
echo "$c cycles in $DUR s"
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
