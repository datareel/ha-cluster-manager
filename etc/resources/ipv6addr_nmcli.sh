#!/bin/bash
# DR cluster resource script for adding or removing IPv6 addresses
#
# IPv6 version of ipv4addr_nmcli.sh. It manages the floating IP
# through NetworkManager (nmcli) and is used on RHEL 8 and later.
# Cluster messages still use IPv4; only the floating IP is IPv6.
#
# This resource script is designed to be used on cluster nodes with
# different device names. The NetworkManager connection name must be
# the same as the device name, and the connection's ipv6.method must
# not be "disabled" or "ignore".

if [ -f ~/.bashrc ]; then . ~/.bashrc; fi

# All IPv6 resouce scripts must use the following args:
#
# ${1} = IPv6 address, example: 2001:db8:122::180
# ${2} = Prefix length, example: 64
# ${3} = Ethernet interfaces, examples: ens192 or 'ens192|eno8303'
# ${4} = actions: start|stop

error_level=0

if [ -z ${1} ]; then
    echo "ERROR - You must specify and IPv6 address"
    error_level=1;
fi

if [ -z ${2} ]; then
    echo "ERROR - You must specify a prefix length"
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
    echo "Usage: ${0} 2001:db8:122::180 64 ens192 start|stop"
    exit $error_level
fi

if [[ "${1}" != *:* ]]; then
    echo "ERROR - ${1} is not an IPv6 address, use ipv4addr_nmcli.sh for IPv4"
    exit 1
fi

if ! [[ "${2}" =~ ^[0-9]+$ ]] || [ ${2} -lt 1 ] || [ ${2} -gt 128 ]; then
    echo "ERROR - IPv6 prefix length must be 1 to 128: ${2}"
    exit 1
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

IPV6METHOD=$(nmcli -g ipv6.method connection show ${ETHINT})
if [ "${IPV6METHOD}" == "disabled" ] || [ "${IPV6METHOD}" == "ignore" ]; then
    echo "ERROR - IPv6 is ${IPV6METHOD} on connection ${ETHINT}"
    echo "To enable IPv6 run: nmcli con mod ${ETHINT} ipv6.method auto"
    exit 1
fi

# "ip addr show to" parses the address, so any valid way of writing
# it (upper case, leading zeros, :: or not) matches the installed address

case "${4}" in
    start)
	if [ -z "$(ip -6 addr show dev ${ETHINT} to ${1}/128)" ]; then
	    echo "Adding ${1}/${2} to ${ETHINT}"
	    nmcli con mod ${ETHINT} +ipv6.addresses ${1}/${2}
	    error_level=$?
	    if [ $error_level -ne 0 ]; then
		echo "ERROR - Command failed: nmcli con mod ${ETHINT} +ipv6.addresses ${1}/${2}"
	    else
		nmcli device reapply ${ETHINT}
		error_level=$?
		if [ $error_level -ne 0 ]; then
		    echo "ERROR - Command failed: nmcli device reapply ${ETHINT}"
		fi
	    fi
	else
	    echo "INFO - ${1}/${2} dev ${ETHINT} already added"
	fi
        ;;
    stop)
	if [ -n "$(ip -6 addr show dev ${ETHINT} to ${1}/128)" ]; then
	    echo "Deleting ${1}/${2} from ${ETHINT}"
	    nmcli con mod ${ETHINT} -ipv6.addresses ${1}/${2}
	    error_level=$?
	    if [ $error_level -ne 0 ]; then
		echo "ERROR - Command failed: nmcli con mod ${ETHINT} -ipv6.addresses ${1}/${2}"
	    else
		nmcli device reapply ${ETHINT}
		error_level=$?
		if [ $error_level -ne 0 ]; then
		    echo "ERROR - Command failed: nmcli device reapply ${ETHINT}"
		fi
	    fi
	else
	    echo "INFO - ${1}/${2} dev ${ETHINT} already deleted"
	fi
        ;;
    *)
        echo "ERROR - Action not valid ${4}"
        exit 1
esac

exit $error_level

# End of resource script
