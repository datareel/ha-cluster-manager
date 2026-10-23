#!/bin/bash
# Copy the DataReel library files used by the DRCM server from a
# DataReel source tree into this repository.
#
# Usage: ./sync_datareel.sh /path/to/datareel
#
# The DRCM build only needs the files listed below. If a DRCM change
# needs another DataReel component, add its .cpp and headers here and
# to build/makefile, env/glibobjs.mak and env/glibdeps.mak.

DATAREEL_DIR="${1}"
if [ -z "${DATAREEL_DIR}" ] || [ ! -d "${DATAREEL_DIR}/include" ] || [ ! -d "${DATAREEL_DIR}/src" ]; then
    echo "Usage: ${0} /path/to/datareel"
    exit 1
fi

SRC_FILES="dfileb futils gthreadt gxcond gxdfp64 gxdfptr gxmutex gxsocket
gxthread logfile strutil systime thelpers thrapiw thrpool ustring"

INCLUDE_FILES="dfileb futils gthreadt gxcond gxd_ver gxdfp64 gxdfptr gxdlcode
gxdtyp64 gxdtypes gxheader gxint32 gxint64 gxlist gxmutex gxsocket gxstring
gxstypes gxthread gxuint32 gxuint64 logfile strutil systime thelpers thrapiw
thrpool thrtypes ustring"

TOP_DIR="$(cd "$(dirname "${0}")/.." && pwd)"

for f in ${SRC_FILES}; do
    cp -fv "${DATAREEL_DIR}/src/${f}.cpp" "${TOP_DIR}/src/${f}.cpp" || exit 1
done

for f in ${INCLUDE_FILES}; do
    cp -fv "${DATAREEL_DIR}/include/${f}.h" "${TOP_DIR}/include/${f}.h" || exit 1
done
