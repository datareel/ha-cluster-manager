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
# Version control: 1.06
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
# Complex locking protocol functions for BASH scripts
#
# This script is designed to be sourced from other scripts.
# Before calling the lock file functions the caller must 
# define the $LOCKfile variable that defined the lock file
# used by the caller to lock a process. 
# ----------------------------------------------------------- 

function CreateLockFile()
{
    hostname=`hostname`
    echo -n "${hostname}:" > ${LOCKfile}
    echo -n $$ >> ${LOCKfile}
    # Other users must not be able to write a PID into the lock file,
    # because LockFileCheck kills the PID it finds there.
    chmod 644 ${LOCKfile}
}

function RemoveLockFile()
{
    rm -f ${LOCKfile}
}

# Returns 0 if the PID is a running process. Matches the PID exactly,
# so PID 12 does not match PID 1234.
function PidIsRunning()
{
    ps -p "${1}" -o pid= &> /dev/null
}

# Kill a process and all of its children, children first.
# Returns 1 if any process is still running afterwards.
function KillProcessTree()
{
    local pid="${1}"
    local child
    for child in $(ps -o pid= --ppid "${pid}" 2> /dev/null); do
	KillProcessTree "${child}" || return 1
    done
    echo "Killing PID ${pid}"
    kill "${pid}" &> /dev/null
    sleep 1
    if PidIsRunning "${pid}"; then
	echo "Could not kill process ${pid}"
	return 1
    fi
    return 0
}

function SimpleLockFileCheck()
{
    MINold="60"
    if [ "$1" != "" ] 
	then 
	MINold="$1"
    fi
    echo "Checking for lock file older than $MINold minutes"
    find ${LOCKfile} -mmin +$MINold -type f -print -exec rm -f {} \; &> /dev/null 
    if [ -e ${LOCKfile} ]
	then
	echo "Lock file still exists: ${LOCKfile}"
	echo "Application may still be running or has terminated before completion"
	echo "Exiting..."
	exit 1
    fi
    echo "Removing the old lock file and continuing to run"
}

function LockFileCheck()
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
	hostname=`hostname`
	if [ "$hostname" != "$LOCKhostname" ]
	    then
	    echo "Process is locked on another node $LOCKhostname"
	    echo "Checking the lock file age, max is $MINold minutes"
	    SimpleLockFileCheck $MINold
	    return 
	fi
	if ! [[ "${LOCKpid}" =~ ^[0-9]+$ ]]
	    then
	    echo "Lock file has no valid PID"
	    echo "Removing the old lock file and continuing to run"
	    rm -f ${LOCKfile}
	    return
	fi
	echo "Checking to see how long the process has been running"
	currlockfile=`find ${LOCKfile} -mmin +$MINold -type f -print`
	if [ "${currlockfile}" == "${LOCKfile}" ]
	    then
	    echo "PID ${LOCKpid} has been running for more than $MINold minutes"
	    if PidIsRunning "${LOCKpid}"
		then
		echo "Attempting to kill the previous process ${LOCKpid} and any children"
		if ! KillProcessTree "${LOCKpid}"
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
	if PidIsRunning "${LOCKpid}"
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
