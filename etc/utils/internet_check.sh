#!/bin/bash
# DRCM isolation check: exits 0 if this node can reach the internet,
# 1 if it cannot. Set in the [CM_SERVER] section of cm.cfg:
#
#   isolation_check = /etc/drcm/utils/internet_check.sh
#
# Usage: internet_check.sh [target ...]
#
# Each target is pinged, and if ICMP is blocked a TCP connection to port
# 53 (DNS) is tried as well. Any one target answering counts as
# connected. The default targets are two public DNS services run by
# different providers, 8.8.8.8 (Google) and 1.1.1.1 (Cloudflare).
#
# The default gateway is pinged too, but only to log whether the LAN or
# the WAN is down. A home or office router keeps answering when its
# internet link fails, so reaching the gateway does not count as
# connected.

TARGETS="${*:-8.8.8.8 1.1.1.1}"
TIMEOUT="${DRCM_CHECK_TIMEOUT:-3}"

reachable() {
    ping -n -q -c 1 -W "${TIMEOUT}" "${1}" &> /dev/null && return 0
    timeout "${TIMEOUT}" bash -c "exec 3<>/dev/tcp/${1}/53" &> /dev/null
}

stamp="$(date '+%F %T') internet_check:"

for t in ${TARGETS}; do
    if reachable "${t}"; then
        exit 0
    fi
done

gateway=$(ip -4 route show default 2> /dev/null | awk '/^default/ { print $3; exit }')
if [ -z "${gateway}" ]; then
    echo "${stamp} FAIL no default route, cannot reach ${TARGETS}"
elif ping -n -q -c 1 -W "${TIMEOUT}" "${gateway}" &> /dev/null; then
    echo "${stamp} FAIL gateway ${gateway} answers but ${TARGETS} do not (WAN down)"
else
    echo "${stamp} FAIL gateway ${gateway} and ${TARGETS} do not answer (LAN down)"
fi
exit 1
