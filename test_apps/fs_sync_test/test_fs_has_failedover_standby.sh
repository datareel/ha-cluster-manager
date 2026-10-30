#!/bin/bash
# Offline test of etc/utils/fs_has_failedover.sh with DRCM 1.43+ standby (no DRCM, no containers):
#   bash test_apps/fs_sync_test/test_fs_has_failedover_standby.sh
HERE=$(cd "$(dirname "$0")" && pwd)
UTIL=${HERE}/../../etc/utils/fs_has_failedover.sh
W=$(mktemp -d); trap 'rm -rf ${W}' EXIT
pass=0; fail=0
cat > ${W}/cluster.sh <<END
export PRIMARY_FILESYSTEMS_HOST=ws
export BACKUP_FILESYSTEMS_HOST=aws
export PRIMARY_FILESYSTEMS_IP=drcm-ws
export BACKUP_FILESYSTEMS_IP=drcm-aws
export PRIMARY_FILESYSTEMS_KEEPALIVE_IP=127.0.0.1
export BACKUP_FILESYSTEMS_KEEPALIVE_IP=127.0.0.2
END
# fake drcm_server --client: WS / AWS = the primary's and backup's status column, PING_WS / PING_AWS = up|down
cat > ${W}/drcm <<'END'
#!/bin/bash
case "$*" in
 *cm_stat*)
    printf "  CM Node     Hostname     Status     IP address\n"
    printf "  ws\tws.example.com\t%s\t127.0.0.1\n" "${WS}"
    printf "  aws1\taws.internal\t%s\t127.0.0.2\n" "${AWS}"
    printf "  Cluster status: %s\n" "${HEALTH}"; exit 0;;
 *-n127.0.0.1*) [ "${PING_WS}" == up ];;
 *-n127.0.0.2*) [ "${PING_AWS}" == up ];;
esac
END
chmod +x ${W}/drcm
t() {   # t WANT description VAR=... (environment of the fake)
    local want=$1 what=$2; shift 2
    got=$(env CFGFILE=${W}/cluster.sh DRCM_server=${W}/drcm "$@" bash ${UTIL})
    [ "${got}" == "${want}" ] && { echo "ok   ${what}"; pass=$((pass+1)); } || { echo "FAIL ${what} (got ${got}, want ${want})"; fail=$((fail+1)); }
}
t FALSE "healthy cluster"                                 WS="Up  " AWS="Up  " HEALTH=HEALTHY PING_WS=up PING_AWS=up
t TRUE  "primary in standby: failed over"                 WS=Standby AWS="Up  " HEALTH="FAILEDOVER resources" PING_WS=up PING_AWS=up
t FALSE "primary still releasing: not yet"                WS=Releasing AWS="Up  " HEALTH="FAILEDOVER resources" PING_WS=up PING_AWS=up
t FALSE "backup in standby: the primary runs everything"  WS="Up  " AWS=Standby HEALTH="FAILEDOVER resources" PING_WS=up PING_AWS=up
t TRUE  "primary down, backup up: failed over (as before)" WS=Down AWS="Up  " HEALTH="DOWN nodes" PING_WS=down PING_AWS=up
t ERROR "both down (as before)"                           WS=Down AWS=Down HEALTH="DOWN nodes" PING_WS=down PING_AWS=down
echo; echo "${pass} passed, ${fail} failed"
[ ${fail} -eq 0 ]
