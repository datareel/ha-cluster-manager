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

${DRCM_server} --client --command=cm_stat | ${GREP} 'Cluster status: HEALTHY' &> /dev/null
if [ $? -eq 0 ]; then
    echo "FALSE"
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
