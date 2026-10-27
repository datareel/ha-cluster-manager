#!/bin/bash
# Scenario tests for the DRCM internet file sync, run on the host
S=$(dirname $(readlink -f $0)); cd $S
# Run ./setup.sh first
pass=0; fail=0
ok()   { echo "PASS - $1"; pass=$((pass+1)); }
bad()  { echo "FAIL - $1"; fail=$((fail+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
ws()   { podman exec ws bash -c "$1"; }
aws()  { podman exec aws bash -c "$1"; }
hg()   { podman exec hg bash -c "$1"; }
state(){ echo "ws=$1 aws=$2" > shared/state; }
sshd_down(){ podman exec $1 pkill -f "ssh --serve"; }
sshd_up(){ podman exec -d $1 bash -c "/usr/local/bin/ssh --serve > /root/sshd.log 2>&1"; sleep 1; }
SYNC=/etc/drcm/file_system_sync/sync_osa.sh
GUARD="/etc/drcm/resources/crontab_fs_guard.sh /etc/drcm/crontabs/osa_crons /root/cron.d"

state up up
for n in ws aws hg; do podman exec $n bash -c 'rm -rf /root/osa_data /backup /var/lib/drcm/* /root/cron.d; mkdir -p /root/cron.d'; done
ws 'mkdir -p /root/osa_data/{trading,logs,proc,var}; echo v1 > /root/osa_data/trading/ledger.json; echo wslog > /root/osa_data/logs/ws.log; echo p > /root/osa_data/proc/tmp1; touch /root/osa_data/trading/trader.lock /root/osa_data/.osa_tam.lock; echo old > /root/osa_data/var/gone.txt'
aws 'mkdir -p /root/osa_data/logs; echo awslog > /root/osa_data/logs/aws.log'

echo "== 1 normal sync, workstation to AWS"
ws $SYNC > /dev/null; echo "rc=$?"
check "ledger copied" "aws 'grep -q v1 /root/osa_data/trading/ledger.json'"
check "logs not copied" "aws '! test -e /root/osa_data/logs/ws.log'"
check "AWS own logs kept by --delete" "aws 'test -e /root/osa_data/logs/aws.log'"
check "proc not copied" "aws '! test -e /root/osa_data/proc/tmp1'"
check "lock files not copied" "aws '! test -e /root/osa_data/trading/trader.lock && ! test -e /root/osa_data/.osa_tam.lock'"
check "3-way: third node got the data" "hg 'grep -q v1 /backup/root/osa_data/trading/ledger.json'"
check "3-way: no logs or locks on third node" "hg '! test -e /backup/root/osa_data/logs/ws.log && ! test -e /backup/root/osa_data/trading/trader.lock'"
aws $SYNC > /dev/null; check "AWS run in normal operation does nothing" "aws '! ls /var/lib/drcm/*flag* 2>/dev/null'"
check "guard installs on primary when no flags" "ws '$GUARD start' >/dev/null && ws 'test -f /root/cron.d/osa_crons'"
ws "$GUARD stop" > /dev/null

echo "== 2 workstation down for the whole fail over"
sshd_down ws; state down up
aws $SYNC > /dev/null
check "AWS writes failback flag" "aws 'test -s /var/lib/drcm/osa_failback_sync_flag'"
check "AWS saw workstation down (ssh check, not ping)" "grep -q 'Primary cluster node is still down' <(aws 'cat /root/drcmlog/aws-osa-filesystem-sync.log')"
aws 'echo v2-aws > /root/osa_data/trading/ledger.json; echo new > /root/osa_data/trading/aws_trade.json; rm /root/osa_data/var/gone.txt'
aws $SYNC > /dev/null
check "3-way: AWS keeps third node current while failed over" "hg 'grep -q v2-aws /backup/root/osa_data/trading/ledger.json && ! test -e /backup/root/osa_data/var/gone.txt'"
echo "-- AWS reboot: /var/run is lost, /var/lib/drcm is not"
check "flag kept in persistent dir" "aws 'test -s /var/lib/drcm/osa_failback_sync_flag'"

echo "== 3 workstation returns, its cron runs before AWS (the race)"
sshd_up ws; state up up
ws $SYNC > /dev/null; echo "rc=$?"
check "3-way: workstation did not push old data to third node" "hg 'grep -q v2-aws /backup/root/osa_data/trading/ledger.json'"
check "workstation did not push old data" "aws 'grep -q v2-aws /root/osa_data/trading/ledger.json && test -e /root/osa_data/trading/aws_trade.json'"
check "workstation copied the flag locally" "ws 'test -s /var/lib/drcm/osa_failback_sync_flag'"
ws "$GUARD start" > /dev/null; check "guard refuses crontab while flag exists" "ws '! test -f /root/cron.d/osa_crons'"
ws 'rm -f /var/lib/drcm/osa_failback_sync_flag'
ws "$GUARD start" > /dev/null; check "guard also sees the flag on AWS" "ws '! test -f /root/cron.d/osa_crons'"

echo "== 4 AWS syncs back"
aws $SYNC > /dev/null; echo "rc=$?"
check "AWS changes on workstation" "ws 'grep -q v2-aws /root/osa_data/trading/ledger.json && test -e /root/osa_data/trading/aws_trade.json'"
check "delete on AWS mirrored back" "ws '! test -e /root/osa_data/var/gone.txt'"
check "workstation logs kept" "ws 'test -e /root/osa_data/logs/ws.log && test -e /root/osa_data/proc/tmp1'"
check "flags cleared on both" "ws '! test -e /var/lib/drcm/osa_failback_sync_flag' && aws '! test -e /var/lib/drcm/osa_failback_sync_flag'"
ws "$GUARD start" > /dev/null; check "guard now installs crontab" "ws 'test -f /root/cron.d/osa_crons'"
ws "$GUARD stop" > /dev/null

echo "== 5 normal sync resumes"
ws 'echo v3 > /root/osa_data/trading/ledger.json'; ws $SYNC > /dev/null
check "workstation pushes again" "aws 'grep -q v3 /root/osa_data/trading/ledger.json'"

echo "== 6 AWS unreachable"
sshd_down aws; state up down
ws 'echo v4 > /root/osa_data/trading/ledger.json'
ws $SYNC > /dev/null; check "workstation sync exits non zero" "[ \$? -ne 0 ]"
check "3-way: workstation still copies to third node with AWS down" "hg 'grep -q v4 /backup/root/osa_data/trading/ledger.json'"
ws "$GUARD start" > /dev/null; check "guard installs when backup unreachable" "ws 'test -f /root/cron.d/osa_crons'"
ws "$GUARD stop" > /dev/null; sshd_up aws; state up up

echo "== 7 flag reached the workstation (link up during fail over)"
state down up; aws $SYNC > /dev/null
check "AWS copied flag to workstation" "ws 'test -s /var/lib/drcm/osa_failback_sync_flag'"
state up up; ws $SYNC > /dev/null; check "workstation skips with local flag" "ws 'test -s /var/lib/drcm/osa_failback_sync_flag'"
aws $SYNC > /dev/null; check "flags cleared after failback" "ws '! test -e /var/lib/drcm/osa_failback_sync_flag' && aws '! test -e /var/lib/drcm/osa_failback_sync_flag'"

echo "== 8 3-way sync every N minutes"
ws 'echo v5 > /root/osa_data/trading/ledger.json'; ws "TERTIARY_SYNC_MINUTES=60 $SYNC" > /dev/null
check "3-way: copy skipped until due" "hg '! grep -q v5 /backup/root/osa_data/trading/ledger.json'"
check "main sync still ran" "aws 'grep -q v5 /root/osa_data/trading/ledger.json'"
ws 'echo 0 > /var/lib/drcm/osa_tertiary_last_sync'; ws "TERTIARY_SYNC_MINUTES=60 $SYNC" > /dev/null
check "3-way: copy runs when due" "hg 'grep -q v5 /backup/root/osa_data/trading/ledger.json'"

echo; echo "passed $pass, failed $fail"
[ $fail -eq 0 ]
