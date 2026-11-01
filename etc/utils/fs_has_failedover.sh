#!/bin/bash

if [ -f ~/.bashrc ]; then . ~/.bashrc; fi

if [ -z "${CFGFILE}" ]; then export CFGFILE=/etc/drcm/my_cluster_conf/my_cluster_info.sh; fi
. ${CFGFILE}
if [ -z "${DRCM_server}" ]; then export DRCM_server="/usr/sbin/drcm_server"; fi
if [ -z "${GREP}" ]; then export GREP="grep"; fi
if [ -z "${PRIMARY_FILESYSTEMS_IP}" ]; then exit 1; fi
if [ -z "${BACKUP_FILESYSTEMS_IP}" ]; then exit 1; fi

# The DRCM keep alive address of each node, when the replication
# address is a host name or ssh alias that drcm_server does not know
PRIMARY_KEEPALIVE="${PRIMARY_FILESYSTEMS_IP}"
BACKUP_KEEPALIVE="${BACKUP_FILESYSTEMS_IP}"
if [ ! -z "${PRIMARY_FILESYSTEMS_KEEPALIVE_IP}" ]; then PRIMARY_KEEPALIVE="${PRIMARY_FILESYSTEMS_KEEPALIVE_IP}"; fi
if [ ! -z "${BACKUP_FILESYSTEMS_KEEPALIVE_IP}" ]; then BACKUP_KEEPALIVE="${BACKUP_FILESYSTEMS_KEEPALIVE_IP}"; fi

STAT=$(${DRCM_server} --client --command=cm_stat 2> /dev/null)

# DRCM 1.43+ standby: a primary in standby has handed its resources to the backup on purpose. It still
# answers pings, so the checks below would call that "not failed over"; report the fail over instead, so
# the backup syncs back to it (failback flag) and the primary waits for that before it runs again.
# Its member line: "  <nodename>\t<hostname>\tStandby\t<keep alive ip>" (Releasing while it stops).
PRIMARY_HOST_SHORT="${PRIMARY_FILESYSTEMS_HOST}"
echo "${STAT}" | awk -F'\t' -v ip="${PRIMARY_KEEPALIVE}" -v h="${PRIMARY_HOST_SHORT}" '
    { split($2, a, "."); sub(/[ \t]+$/, "", $4) }
    ($4 == ip || (h != "" && a[1] == h)) && $3 ~ /^Standby/ { f = 1 }
    END { exit !f }'
if [ $? -eq 0 ]; then
    echo "TRUE"
    exit 0
fi

echo "${STAT}" | ${GREP} 'Cluster status: HEALTHY' &> /dev/null
if [ $? -eq 0 ]; then
    echo "FALSE"
    exit 0
fi

# Failed over means the backup runs the cluster's resources: a resource line in cm_stat with the status
# OK-Backup ("   Crontab:\t<nickname>\t<owner>\tOK-Backup\t<start time>", the same for the other resource
# types). A peer that only looks Down is not a fail over: with just the cluster link cut (SSH tunnel down,
# 2026-11-01 test) the takeover check kept the resources where they were, yet the ping checks below said
# TRUE, so the backup's node gate allowed jobs and its file sync wrote failback flags, which would have
# copied the backup's older data over the primary's at the next failback sync. When cm_stat answers, its
# resources decide; the ping checks are only for a node whose own drcm_server does not answer.
if [ -n "${STAT}" ] && echo "${STAT}" | ${GREP} -q 'Cluster status:'; then
    if echo "${STAT}" | awk -F'\t' '$4 ~ /^OK-Backup/ { f = 1 } END { exit !f }'; then
        echo "TRUE"
    else
        echo "FALSE"
    fi
    exit 0
fi

${DRCM_server} --client --command=ping -c5 -n"${PRIMARY_KEEPALIVE}" &> /dev/null
if [ $? -eq 0 ]; then
    echo "FALSE"
    exit 0
fi

${DRCM_server} --client --command=ping -c5 -n"${BACKUP_KEEPALIVE}" &> /dev/null
if [ $? -eq 0 ]; then
    echo "TRUE"
    exit 0
else
    echo "ERROR"
    exit 1
fi
