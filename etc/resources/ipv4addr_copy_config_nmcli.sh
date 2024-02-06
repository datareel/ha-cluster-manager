#!/usr/bin/bash
# DR cluster resource script for adding or removing IPv4 addresses

. ~/.bashrc

# All IPv4 resouce scripts must use the following args:
#
# ${1} = IP address, example: 192.168.122.24
# ${2} = Netmask, examples: 255.255.255.0 or CIDR notation: 24
# ${3} = Ethernet interfaces, example: 'eth0:1|ens192:0|em1:0'
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
    echo "ERROR - You must specify a group of Ethernet interfaces"
    error_level=1;
fi

if [ -z ${4} ]; then
    echo "ERROR - You must specify an action"
    error_level=1;
fi

if [ $error_level -ne 0 ]; then
    echo "Usage: ${0} 192.168.122.25 24 eth0:1|ens192:0|em1:0 start|stop"
    exit $error_level
fi

SAVEIFS=$IFS
IFS='|'
for i in ${3}; do
    nmcli -t -f NAME c show --active | grep ${i} &> /dev/null
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

START_f="/etc/drcm/my_cluster_conf/$(hostname -s)_start_backup_ip_${ETHINT}"
STOP_f="/etc/drcm/my_cluster_conf/$(hostname -s)_stop_backup_ip_${ETHINT}"

if [ ! -f ${START_f} ]; then
    echo "ERROR - Missing file: ${START_f}"
    echo "To Create a template run:"
    echo "cp /etc/NetworkManager/system-connections/${ETHINT}.nmconnection ${START_f}"
    error_level=1;
fi

if [ ! -f ${STOP_f} ]; then
    echo "ERROR - Missing file: ${STOP_f}"
    echo "To Create a template run:"
    echo "cp /etc/NetworkManager/system-connections/${ETHINT}.nmconnection ${STOP_f}"
    error_level=1;
fi

if [ $error_level -ne 0 ]; then
    exit $error_level
fi

case "${4}" in
    start)
	ip addr show ${ETHINT} | grep "${1}/" &> /dev/null
	if [ $? -ne 0 ]; then
	    echo "Adding ${1}/${2} to ${ETHINT}"
	    echo "Copy file: ${START_f}"
	    cat ${START_f} > /etc/NetworkManager/system-connections/${ETHINT}.nmconnection
	    # Reload new connection profile from disk
	    nmcli connection reload
	    error_level=$?
	    if [ $error_level -ne 0 ]; then 
		echo "ERROR - Command failed: nmcli connection reload"
	    else
		# Reapply new profile to the active connection
		nmcli device reapply ${ETHINT}
		error_level=$?
		if [ $error_level -ne 0 ]; then 
		    echo "ERROR - Command failed: nmcli device reapply enp1s0"
		fi
	    fi
	else 
	    echo "INFO - ${1}/${2} dev ${ETHINT} already added"
	fi
        ;;
    stop)
	cat /etc/NetworkManager/system-connections/${ETHINT}.nmconnection | grep "${1}/" &> /dev/null
	if [ $? -eq 0 ]; then
	    cat ${STOP_f} > /etc/NetworkManager/system-connections/${ETHINT}.nmconnection
	    # Reload new connection profile from disk
	    nmcli connection reload
	    error_level=$?
	    if [ $error_level -ne 0 ]; then 
		echo "ERROR - Command failed: nmcli connection reload"
	    else
		# Reapply new profile to the active connection
		nmcli device reapply ${ETHINT}
		error_level=$?
		if [ $error_level -ne 0 ]; then 
		    echo "ERROR - Command failed: nmcli device reapply enp1s0"
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
