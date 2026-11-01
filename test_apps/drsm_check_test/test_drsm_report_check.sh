#!/bin/bash
# Offline tests of etc/utils/drsm_report_check.sh with a fake curl (no dashboard needed):
# agent_age_secs is used when the dashboard gives it, age_secs otherwise; --fail-closed on errors.
#   bash test_apps/drsm_check_test/test_drsm_report_check.sh
HERE=$(cd "$(dirname "$0")" && pwd)
CHECK=${HERE}/../../etc/utils/drsm_report_check.sh
T=$(mktemp -d); trap 'rm -rf "${T}"' EXIT
pass=0; fail=0
run() {   # $1 = expected exit, $2 = name, $3 = fake reply ('' = curl fails), rest = check args
    local want=$1 name=$2 reply=$3; shift 3
    printf '#!/bin/bash\n%s\n' "$( [ -n "${reply}" ] && echo "echo '${reply}'" || echo 'exit 22')" > ${T}/curl
    chmod +x ${T}/curl
    out=$(PATH=${T}:${PATH} bash ${CHECK} --url https://example.invalid/dashboard "$@" node1 2>&1); rc=$?
    if [ ${rc} -eq ${want} ]; then pass=$((pass+1)); echo "ok   ${name}: ${out#* node1: }"
    else fail=$((fail+1)); echo "FAIL ${name}: exit ${rc}, want ${want}: ${out}"; fi
}
# the 2026-11-01 failover test: the agent silent 29 minutes, the dashboard's own run 272 s ago
run 0 "agent silent, dashboard run fresh: down (takeover)" \
    '{"host":"node1","time":1,"age_secs":272,"agent_age_secs":1740,"state":"WARNING","stale":false}' --fail-closed
run 1 "agent reported recently: alive" \
    '{"host":"node1","time":1,"age_secs":272,"agent_age_secs":300,"state":"OK","stale":false}' --fail-closed
run 1 "no agent_age_secs, fresh age_secs: alive (older dashboards)" \
    '{"host":"node1","time":1,"age_secs":272,"state":"OK","stale":false}' --fail-closed
run 0 "no agent_age_secs, old age_secs: down" \
    '{"host":"node1","time":1,"age_secs":1500,"state":"OK","stale":false}' --fail-closed
run 1 "agent_age_secs under a custom --max-age: alive" \
    '{"host":"node1","age_secs":10,"agent_age_secs":250}' --max-age 300 --fail-closed
run 0 "agent_age_secs over a custom --max-age: down" \
    '{"host":"node1","age_secs":10,"agent_age_secs":301}' --max-age 300 --fail-closed
run 1 "dashboard unreadable, --fail-closed: no takeover" '' --fail-closed
run 0 "dashboard unreadable, fail open: takeover" ''
run 1 "no ages at all, --fail-closed: no takeover" '{"host":"node1"}' --fail-closed
echo ""; echo "${pass} passed, ${fail} failed"
[ ${fail} -eq 0 ]
