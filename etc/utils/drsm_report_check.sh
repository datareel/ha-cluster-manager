#!/bin/bash
# DRCM takeover check: asks a DRSM dashboard when the dead peer last
# reported. Set in the [CM_SERVER] section of cm.cfg:
#
#   takeover_check = /etc/drcm/utils/drsm_report_check.sh --url https://datareel.com/dashboard
#
# DRCM adds the peer's nodename as the last argument before a takeover.
#
# Usage: drsm_report_check.sh --url DASHBOARD_URL [--max-age SECS]
#                             [--host NODENAME=DRSM_HOST] [--fail-closed] NODENAME
#
# Exit 0: the peer's last report is older than --max-age (default 1200
# seconds), so it is down and the takeover may go ahead.
# Exit 1: the peer reported recently. It is alive and only the cluster
# link is broken, so do not take over.
#
# The DRSM monitor on the peer copies its reports to the dashboard on
# another server (drsm_web_sync.sh), so the dashboard sees the peer by a
# path that does not use the cluster link. Pick --max-age above the DRSM
# run interval plus the copy time: 1200 fits the 15 minute default.
#
# The dashboard page php/host_status.php needs a login, so the server
# running this check must be in the dashboard's $AUTHnetworks list.
#
# When the dashboard cannot be read, the takeover goes ahead (exit 0)
# and a WARNING is logged, so a dashboard outage cannot block a real
# failover. --fail-closed refuses the takeover instead (exit 1).

URL=""
MAX_AGE=1200
FAIL_CLOSED=0
declare -A HOSTMAP

usage() {
    echo "Usage: ${0} --url DASHBOARD_URL [--max-age SECS] [--host NODENAME=DRSM_HOST] [--fail-closed] NODENAME"
    exit 2
}

while [ $# -gt 1 ]; do
    case "${1}" in
        --url) URL="${2%/}"; shift ;;
        --max-age) MAX_AGE="${2}"; shift ;;
        --host) HOSTMAP["${2%%=*}"]="${2#*=}"; shift ;;
        --fail-closed) FAIL_CLOSED=1 ;;
        *) usage ;;
    esac
    shift
done
NODE="${1}"
if [ -z "${URL}" ] || [ -z "${NODE}" ]; then usage; fi
if ! [[ "${MAX_AGE}" =~ ^[0-9]+$ ]]; then usage; fi

HOST="${HOSTMAP[${NODE}]:-${NODE}}"
stamp="$(date '+%F %T') drsm_report_check ${NODE}:"

unreadable() {
    if [ ${FAIL_CLOSED} -eq 1 ]; then
        echo "${stamp} WARNING ${1}, --fail-closed so no takeover"
        exit 1
    fi
    echo "${stamp} WARNING ${1}, allowing the takeover"
    exit 0
}

json=$(curl -s -f --connect-timeout 10 --max-time 20 "${URL}/php/host_status.php?n=${HOST}" 2> /dev/null)
if [ $? -ne 0 ] || [ -z "${json}" ]; then
    unreadable "cannot read ${URL}/php/host_status.php for ${HOST}"
fi
age=$(echo "${json}" | grep -o '"age_secs":-\?[0-9]*' | cut -d: -f2)
if [ -z "${age}" ]; then
    unreadable "no age_secs in the dashboard reply for ${HOST}"
fi

if [ "${age}" -lt "${MAX_AGE}" ]; then
    echo "${stamp} ALIVE ${HOST} reported to the dashboard ${age}s ago (under ${MAX_AGE}s), it is still alive"
    exit 1
fi
echo "${stamp} DOWN ${HOST} last reported ${age}s ago (over ${MAX_AGE}s), it is down"
exit 0
