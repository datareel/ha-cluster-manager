#!/bin/bash
# ----------------------------------------------------------- 
# BASH Script
# Operating System(s): RHEL/CENTOS
# Run Level(s): 3, 5
# Shell: BASH shell
# Original Author(s): DataReel Software Development
# File Creation Date: 07/17/2016 
# Date Last Modified: 10/23/2026
#
# Version control: 1.09
#
# Contributor(s):
# ----------------------------------------------------------- 
# ------------- Program Description and Details ------------- 
# ----------------------------------------------------------- 
# This file is part of the DataReel software distribution.
#
# Datareel is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. 
#
# Datareel software is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with the DataReel software distribution.  If not, see
# <http://www.gnu.org/licenses/>.
#
#
# Complex locking protocol functions for BASH scripts
#
# Modified version of process_lock.sh script for clusters.
#
# NOTE: This script requires a trust relationship using SSH
# NOTE: keys to check the process on another server.
# NOTE: The lock file directory has to be NFS mounted between
# NOTE: the cluster nodes.
#
# This script is designed to be sourced from other scripts.
# Before calling the lock file functions the caller must 
# define the $LOCKfile variable that defined the lock file
# used by the caller to lock a process. 
# ----------------------------------------------------------- 


# SSH options for checking the lock owner on another node. The node
# host keys must be known: accept-new trusts a key the first time and
# refuses a key that changes. Set DRCM_SSH_OPTS to override.
if [ -z "${DRCM_SSH_OPTS}" ]; then DRCM_SSH_OPTS="-x -q -o BatchMode=yes -o StrictHostKeyChecking=accept-new"; fi

function NetCreateLockFile()
{
    hostname=`hostname`
    echo -n "${hostname}:" > ${LOCKfile}
    echo -n $$ >> ${LOCKfile}
    # Other users must not be able to write a PID into the lock file,
    # because NetLockFileCheck kills the PID it finds there.
    chmod 644 ${LOCKfile}
}

function NetRemoveLockFile()
{
    rm -f ${LOCKfile}
}

# Returns 0 if the PID is running on the lock owner's node
function NetPidIsRunning()
{
    ssh ${DRCM_SSH_OPTS} "${LOCKhostname}" "ps -p ${1} -o pid=" &> /dev/null
}

# Kill a process and all of its children on the lock owner's node,
# children first. Returns 1 if any process is still running afterwards.
function NetKillProcessTree()
{
    local pid="${1}"
    local child
    for child in $(ssh ${DRCM_SSH_OPTS} "${LOCKhostname}" "ps -o pid= --ppid ${pid}" 2> /dev/null); do
	[[ "${child}" =~ ^[0-9]+$ ]] || continue
	NetKillProcessTree "${child}" || return 1
    done
    echo "Killing PID ${pid} on ${LOCKhostname}"
    ssh ${DRCM_SSH_OPTS} "${LOCKhostname}" "kill ${pid}" &> /dev/null
    sleep 1
    if NetPidIsRunning "${pid}"; then
	echo "Could not kill process ${pid} on ${LOCKhostname}"
	return 1
    fi
    return 0
}

function NetLockFileCheck()
{
    MINold="60"
    if [ "$1" != "" ] 
	then 
	MINold="$1"
    fi
    if [ -e ${LOCKfile} ]
	then
	echo "A lock file exists: ${LOCKfile}"
	LOCKhostname=`awk -F: '{ print $1 }' ${LOCKfile}`
	LOCKpid=`awk -F: '{ print $2 }' ${LOCKfile}`
	echo "Process is locked on $LOCKhostname"
	if ! [[ "${LOCKpid}" =~ ^[0-9]+$ ]] || ! [[ "${LOCKhostname}" =~ ^[A-Za-z0-9._-]+$ ]]
	    then
	    echo "Lock file has no valid hostname or PID"
	    echo "Removing the old lock file and continuing to run"
	    rm -f ${LOCKfile}
	    return
	fi
	echo "Checking to see how long the process has been running"
	currlockfile=`find ${LOCKfile} -mmin +$MINold -type f -print`
	if [ "${currlockfile}" == "${LOCKfile}" ]
	    then
	    echo "PID ${LOCKpid} has been running for more than $MINold minutes"
	    if NetPidIsRunning "${LOCKpid}"
		then
		echo "Attempting to kill the previous process ${LOCKpid} and any children"
		if ! NetKillProcessTree "${LOCKpid}"
		    then
		    echo "${LOCKpid}  process is still running" 
		    echo "Application may be running or has terminated before completion"
		    echo "Exiting..."
		    exit 1
		fi
	    else
		echo "PID ${LOCKpid} is not running"
		echo "Removing the old lock file and continuing to run"
		rm -f ${LOCKfile}
		return
	    fi
	fi
	echo "Checking to see if the previous process is still running"
	if NetPidIsRunning "${LOCKpid}"
	    then
	    echo "${LOCKpid}  process is still running" 
	    echo "Application may be running or has terminated before completion"
	    echo "Exiting..."
	    exit 1
	fi
	echo "Previous process is not running"
	echo "Removing the old lock file and continuing to run"
	rm -f ${LOCKfile}
    fi
}
