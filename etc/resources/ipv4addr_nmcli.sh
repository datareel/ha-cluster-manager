#!/bin/bash
# DR cluster resource script for adding or removing IPv4 addresses
#
# This is the default floating IP resource script. It manages the
# address through NetworkManager (nmcli) and is used on RHEL 8 and
# later. The legacy network-scripts (ifcfg) resource scripts are only
# for older systems that do not run NetworkManager.
#
# This resource script is designed to be used on cluster nodes with
# different device names. The NetworkManager connection name must be
# the same as the device name.

if [ -f ~/.bashrc ]; then . ~/.bashrc; fi

# All IPv4 resouce scripts must use the following args:
#
# ${1} = IP address, example: 192.168.122.24
# ${2} = Netmask, examples: 255.255.255.0 or CIDR notation: 24
# ${3} = Ethernet interfaces, examples: ens192 or 'ens192|eno8303'
# ${4} = actions: start|stop

error_level=0

if [ -z ${1} ]; then
    echo "ERROR - You must specify and IPv4 address"
    error_level=1;
fi

if [ -z ${2} ]; then
    echo "ERROR - You must specify a netmask"
    error_level=1;
fi

if [ -z ${3} ]; then
    echo "ERROR - You must specify an Ethernet interface or | seperated list"
    error_level=1;
fi

if [ -z ${4} ]; then
    echo "ERROR - You must specify an action"
    error_level=1;
fi

if [ $error_level -ne 0 ]; then
    echo "Usage: ${0} 192.168.122.25 24 ens192 start|stop"
    exit $error_level
fi

# nmcli only accepts a CIDR prefix, so convert a dotted netmask
# (255.255.255.0) to a prefix (24)
PREFIX="${2}"
if [[ "${PREFIX}" == *.* ]]; then
    PREFIX=0
    SAVEIFS=$IFS
    IFS='.'
    for octet in ${2}; do
	while [ ${octet} -gt 0 ]; do
	    PREFIX=$((PREFIX + (octet & 1)))
	    octet=$((octet >> 1))
	done
    done
    IFS=$SAVEIFS
fi

SAVEIFS=$IFS
IFS='|'
for i in ${3}; do
    nmcli -t -f NAME c show --active | grep -Fx "${i}" &> /dev/null
    if [ $? -eq 0 ]; then
	ETHINT="${i}"
	break
    fi
done
IFS=$SAVEIFS

if [ -z ${ETHINT} ]; then
    echo "ERROR - No interface was found for ${3}"
    error_level=1;
fi

if [ $error_level -ne 0 ]; then
    exit $error_level
fi

case "${4}" in
    start)
	ip addr show ${ETHINT} | grep -F " ${1}/" &> /dev/null
	if [ $? -ne 0 ]; then
	    echo "Adding ${1}/${PREFIX} to ${ETHINT}"
	    nmcli con mod ${ETHINT} +ipv4.address ${1}/${PREFIX}
	    error_level=$?
	    if [ $error_level -ne 0 ]; then 
		echo "ERROR - Command failed: nmcli con mod ${ETHINT} +ipv4.address ${1}/${PREFIX}"
	    else
		nmcli device reapply ${ETHINT}
		error_level=$?
		if [ $error_level -ne 0 ]; then 
		    echo "ERROR - Command failed: nmcli device reapply ${ETHINT}"
		fi
	    fi
	else 
	    echo "INFO - ${1}/${PREFIX} dev ${ETHINT} already added" 
	fi
        ;;
    stop)
	ip addr show ${ETHINT} | grep -F " ${1}/" &> /dev/null
	if [ $? -eq 0 ]; then
	    echo "Deleting ${1}/${PREFIX} to ${ETHINT}"
	    nmcli con mod ${ETHINT} -ipv4.address ${1}/${PREFIX}
	    error_level=$?
	    if [ $error_level -ne 0 ]; then 
		echo "ERROR - Command failed: nmcli con mod ${ETHINT} -ipv4.address ${1}/${PREFIX}"
	    else
		nmcli device reapply ${ETHINT}
		error_level=$?
		if [ $error_level -ne 0 ]; then 
		    echo "ERROR - Command failed: nmcli device reapply ${ETHINT}"
		fi
	    fi
	else 
	    echo "INFO - ${1}/${PREFIX} dev ${ETHINT} already deleted" 
	fi
        ;;
    *)
        echo "ERROR - Action not valid ${4}"
        exit 1
esac

exit $error_level

# End of resource script
