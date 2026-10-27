#!/bin/bash
# BASH Script
# Operating System(s): RHEL/CENTOS
# Run Level(s): 3, 5
# Shell: BASH shell
# Original Author(s): DataReel Software Development
# File Creation Date: 10/26/2026
# Date Last Modified: 10/26/2026
#
# Version control: 1.00
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
# Crontab resource for jobs that use 2-way replicated file systems.
#
# Works like crontab.sh, but on the primary file system node a start
# is refused while a failback sync flag exists on this node or on the
# backup node. The jobs then do not run on old data before the backup
# has copied its changes back. DRCM retries the start at every
# crontabs_check, so the crontab is installed once the sync is done.
#
# CSV format in cm.cfg:
# nickname, template_file, install_location, /etc/drcm/resources/crontab_fs_guard.sh
#
# -----------------------------------------------------------

if [ -f ~/.bashrc ]; then . ~/.bashrc; fi

if [ -z "${CFGFILE}" ]; then export CFGFILE=/etc/drcm/my_cluster_conf/my_cluster_info.sh; fi
if [ -z "${DRCMdir}" ]; then export DRCMdir="/etc/drcm"; fi
if [ -z "${SSH}" ]; then export SSH="ssh"; fi
if [ -z "${DRCM_SSH_OPTS}" ]; then export DRCM_SSH_OPTS="-o StrictHostKeyChecking=accept-new"; fi

if [ "${3}" == "start" ] && [ -f ${CFGFILE} ]; then
    . ${CFGFILE}
    if [ -z "${VARdir}" ]; then export VARdir="/var/lib/drcm"; fi
    isprimary=$(${DRCMdir}/utils/is_primary_fs.sh)
    if [ "${isprimary}" == "TRUE" ]; then
	if ls ${VARdir}/*_failback_sync_flag &> /dev/null; then
	    echo "$(date) - Not installing $(basename ${1}), failback sync flag on this node:"
	    ls ${VARdir}/*_failback_sync_flag
	    exit 1
	fi

	BACKUPNODE="${BACKUP_FILESYSTEMS_IP}"
	if [ ! -z "${BACKUP_FILESYSTEMS_RSYNC_IP}" ]; then BACKUPNODE="${BACKUP_FILESYSTEMS_RSYNC_IP}"; fi
	REMOTEcheck="${SSH} ${DRCM_SSH_OPTS} -n -o BatchMode=yes -o ConnectTimeout=15 ${BACKUPNODE} ls ${VARdir}/*_failback_sync_flag"
	if [ "$(whoami)" != "${BACKUP_USER}" ] && [ ! -z "${BACKUP_USER}" ]; then
	    # The ssh keys belong to the backup user
	    flags=$(runuser -u ${BACKUP_USER} -- ${REMOTEcheck} 2> /dev/null)
	    rv=$?
	else
	    flags=$(${REMOTEcheck} 2> /dev/null)
	    rv=$?
	fi
	if [ $rv -eq 0 ] && [ ! -z "${flags}" ]; then
	    echo "$(date) - Not installing $(basename ${1}), failback sync flag on ${BACKUPNODE}:"
	    echo "${flags}"
	    exit 1
	fi
	# ls exits 2 when there are no flags. Any other failure means the
	# backup cannot be reached, and the primary must still run.
	if [ $rv -ne 0 ] && [ $rv -ne 2 ]; then
	    echo "$(date) - WARNING - Cannot check ${BACKUPNODE} for failback sync flags, installing $(basename ${1})"
	fi
    fi
fi

exec ${DRCMdir}/resources/crontab.sh "${1}" "${2}" "${3}"
