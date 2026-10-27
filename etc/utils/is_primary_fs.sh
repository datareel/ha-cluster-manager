#!/bin/bash

if [ -f ~/.bashrc ]; then . ~/.bashrc; fi

if [ -z "${CFGFILE}" ]; then export CFGFILE=/etc/drcm/my_cluster_conf/my_cluster_info.sh; fi
. ${CFGFILE}
if [ -z "${IP}" ]; then export IP="ip"; fi

# Nodes that reach each other through a tunnel or NAT do not carry the
# replication address on a local interface, so the role can be set by
# host name instead (hostname -s)
if [ ! -z "${PRIMARY_FILESYSTEMS_HOST}" ]; then
    if [ "$(hostname -s)" == "${PRIMARY_FILESYSTEMS_HOST}" ]; then
	echo "TRUE"
    else
	echo "FALSE"
    fi
    exit 0
fi

if [ -z "${GREP}" ]; then export GREP="grep"; fi
if [ -z "${PRIMARY_FILESYSTEMS_ETH}" ]; then exit 1; fi
if [ -z "${PRIMARY_FILESYSTEMS_IP}" ]; then exit 1; fi

${IP} add show ${PRIMARY_FILESYSTEMS_ETH} | ${GREP} inet | ${GREP} ${PRIMARY_FILESYSTEMS_IP} > /dev/null
if [ $? -eq 0 ]; then
    echo "TRUE"
else
    echo "FALSE"
fi

exit 0
