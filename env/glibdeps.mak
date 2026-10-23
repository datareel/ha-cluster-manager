#######################
#### Start of File ####
#######################
# --------------------------------------------------------------- 
# Makefile Contents: Makefile for the DataReel library components
# C/C++ Compiler Used: GNU, Intel, Cray
# Produced By: DataReel Software Development Team
# File Creation Date: 08/15/2000
# Date Last Modified: 10/23/2026
# --------------------------------------------------------------- 
# --------------- Makefile Description and Details -------------- 
# --------------------------------------------------------------- 
# This makefile contains all the build dependency rules for the subset of the
# DataReel library used by the DRCM server. Only the library
# components the DRCM server links against are included.
# --------------------------------------------------------------- 

# Define the $(GCODE_LIB_DIR) macro in the main makefile for this application
# My directory path for the DataReel library
# GCODE_LIB_DIR =

# Define the $(PATHSEP) macro in the main makefile for this application
# Macro for path separator
# PATHSEP =

# Datareel include path
GLIB_INCLUDE_PATH = $(GCODE_LIB_DIR)$(PATHSEP)include$(PATHSEP)

# Build dependency rules
# ===============================================================
DFILEB_DEP = $(GLIB_INCLUDE_PATH)dfileb.h \
	$(GLIB_INCLUDE_PATH)futils.h \
	$(GLIB_INCLUDE_PATH)gxd_ver.h \
	$(GLIB_INCLUDE_PATH)gxdfp64.h \
	$(GLIB_INCLUDE_PATH)gxdfptr.h \
	$(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxdtyp64.h \
	$(GLIB_INCLUDE_PATH)gxdtypes.h \
	$(GLIB_INCLUDE_PATH)gxheader.h \
	$(GLIB_INCLUDE_PATH)gxint32.h \
	$(GLIB_INCLUDE_PATH)gxint64.h \
	$(GLIB_INCLUDE_PATH)gxuint32.h \
	$(GLIB_INCLUDE_PATH)gxuint64.h \
	$(GLIB_INCLUDE_PATH)strutil.h \
	$(GLIB_INCLUDE_PATH)ustring.h

FUTILS_DEP = $(GLIB_INCLUDE_PATH)futils.h \
	$(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxdtyp64.h

GTHREADT_DEP = $(GLIB_INCLUDE_PATH)gthreadt.h \
	$(GLIB_INCLUDE_PATH)gxcond.h \
	$(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxmutex.h \
	$(GLIB_INCLUDE_PATH)gxthread.h \
	$(GLIB_INCLUDE_PATH)thelpers.h \
	$(GLIB_INCLUDE_PATH)thrpool.h \
	$(GLIB_INCLUDE_PATH)thrtypes.h

GXCOND_DEP = $(GLIB_INCLUDE_PATH)gxcond.h \
	$(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxmutex.h \
	$(GLIB_INCLUDE_PATH)thelpers.h \
	$(GLIB_INCLUDE_PATH)thrtypes.h

GXDFP64_DEP = $(GLIB_INCLUDE_PATH)gxd_ver.h \
	$(GLIB_INCLUDE_PATH)gxdfp64.h \
	$(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxdtyp64.h \
	$(GLIB_INCLUDE_PATH)gxdtypes.h \
	$(GLIB_INCLUDE_PATH)gxheader.h \
	$(GLIB_INCLUDE_PATH)gxint32.h \
	$(GLIB_INCLUDE_PATH)gxint64.h \
	$(GLIB_INCLUDE_PATH)gxuint32.h \
	$(GLIB_INCLUDE_PATH)gxuint64.h

GXDFPTR_DEP = $(GLIB_INCLUDE_PATH)gxd_ver.h \
	$(GLIB_INCLUDE_PATH)gxdfp64.h \
	$(GLIB_INCLUDE_PATH)gxdfptr.h \
	$(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxdtyp64.h \
	$(GLIB_INCLUDE_PATH)gxdtypes.h \
	$(GLIB_INCLUDE_PATH)gxheader.h \
	$(GLIB_INCLUDE_PATH)gxint32.h \
	$(GLIB_INCLUDE_PATH)gxint64.h \
	$(GLIB_INCLUDE_PATH)gxuint32.h \
	$(GLIB_INCLUDE_PATH)gxuint64.h

GXMUTEX_DEP = $(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxmutex.h \
	$(GLIB_INCLUDE_PATH)thelpers.h \
	$(GLIB_INCLUDE_PATH)thrtypes.h

GXSOCKET_DEP = $(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxsocket.h \
	$(GLIB_INCLUDE_PATH)gxstypes.h

GXTHREAD_DEP = $(GLIB_INCLUDE_PATH)gthreadt.h \
	$(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxthread.h \
	$(GLIB_INCLUDE_PATH)thrapiw.h \
	$(GLIB_INCLUDE_PATH)thrpool.h \
	$(GLIB_INCLUDE_PATH)thrtypes.h

LOGFILE_DEP = $(GLIB_INCLUDE_PATH)dfileb.h \
	$(GLIB_INCLUDE_PATH)futils.h \
	$(GLIB_INCLUDE_PATH)gxd_ver.h \
	$(GLIB_INCLUDE_PATH)gxdfp64.h \
	$(GLIB_INCLUDE_PATH)gxdfptr.h \
	$(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxdtyp64.h \
	$(GLIB_INCLUDE_PATH)gxdtypes.h \
	$(GLIB_INCLUDE_PATH)gxheader.h \
	$(GLIB_INCLUDE_PATH)gxint32.h \
	$(GLIB_INCLUDE_PATH)gxint64.h \
	$(GLIB_INCLUDE_PATH)gxuint32.h \
	$(GLIB_INCLUDE_PATH)gxuint64.h \
	$(GLIB_INCLUDE_PATH)logfile.h \
	$(GLIB_INCLUDE_PATH)strutil.h \
	$(GLIB_INCLUDE_PATH)systime.h \
	$(GLIB_INCLUDE_PATH)ustring.h

STRUTIL_DEP = $(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxdtyp64.h \
	$(GLIB_INCLUDE_PATH)strutil.h

SYSTIME_DEP = $(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxdtyp64.h \
	$(GLIB_INCLUDE_PATH)strutil.h \
	$(GLIB_INCLUDE_PATH)systime.h \
	$(GLIB_INCLUDE_PATH)ustring.h

THELPERS_DEP = $(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)thelpers.h \
	$(GLIB_INCLUDE_PATH)thrtypes.h

THRAPIW_DEP = $(GLIB_INCLUDE_PATH)gthreadt.h \
	$(GLIB_INCLUDE_PATH)gxcond.h \
	$(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxmutex.h \
	$(GLIB_INCLUDE_PATH)gxthread.h \
	$(GLIB_INCLUDE_PATH)thelpers.h \
	$(GLIB_INCLUDE_PATH)thrapiw.h \
	$(GLIB_INCLUDE_PATH)thrpool.h \
	$(GLIB_INCLUDE_PATH)thrtypes.h

THRPOOL_DEP = $(GLIB_INCLUDE_PATH)gthreadt.h \
	$(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)thrpool.h \
	$(GLIB_INCLUDE_PATH)thrtypes.h

USTRING_DEP = $(GLIB_INCLUDE_PATH)gxdlcode.h \
	$(GLIB_INCLUDE_PATH)gxdtyp64.h \
	$(GLIB_INCLUDE_PATH)strutil.h \
	$(GLIB_INCLUDE_PATH)ustring.h
# --------------------------------------------------------------- 
#####################
#### End of File ####
#####################
