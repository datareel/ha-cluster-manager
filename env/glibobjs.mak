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
# This makefile contains all the build rules for the subset of the
# DataReel library used by the DRCM server. Only the library
# components the DRCM server links against are included.
# --------------------------------------------------------------- 

# Define the $(GCODE_LIB_DIR) macro in the main makefile for this application
# My directory path for the DataReel library
# GCODE_LIB_DIR =

# Define the $(PATHSEP) macro in the main makefile for this application
# Macro for path separator
# PATHSEP =

# Define the $(OBJ_EXT) macro in the main makefile for this application
# Object file dot extension
# OBJ_EXT =

# Datareel source code path
GLIB_SRC_PATH = $(GCODE_LIB_DIR)$(PATHSEP)src$(PATHSEP)

# Rules to compile library components 
# ===============================================================
dfileb$(OBJ_EXT):	$(GLIB_SRC_PATH)dfileb.cpp $(DFILEB_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)dfileb.cpp

futils$(OBJ_EXT):	$(GLIB_SRC_PATH)futils.cpp $(FUTILS_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)futils.cpp

gthreadt$(OBJ_EXT):	$(GLIB_SRC_PATH)gthreadt.cpp $(GTHREADT_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)gthreadt.cpp

gxcond$(OBJ_EXT):	$(GLIB_SRC_PATH)gxcond.cpp $(GXCOND_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)gxcond.cpp

gxdfp64$(OBJ_EXT):	$(GLIB_SRC_PATH)gxdfp64.cpp $(GXDFP64_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)gxdfp64.cpp

gxdfptr$(OBJ_EXT):	$(GLIB_SRC_PATH)gxdfptr.cpp $(GXDFPTR_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)gxdfptr.cpp

gxmutex$(OBJ_EXT):	$(GLIB_SRC_PATH)gxmutex.cpp $(GXMUTEX_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)gxmutex.cpp

gxsocket$(OBJ_EXT):	$(GLIB_SRC_PATH)gxsocket.cpp $(GXSOCKET_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)gxsocket.cpp

gxthread$(OBJ_EXT):	$(GLIB_SRC_PATH)gxthread.cpp $(GXTHREAD_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)gxthread.cpp

logfile$(OBJ_EXT):	$(GLIB_SRC_PATH)logfile.cpp $(LOGFILE_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)logfile.cpp

strutil$(OBJ_EXT):	$(GLIB_SRC_PATH)strutil.cpp $(STRUTIL_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)strutil.cpp

systime$(OBJ_EXT):	$(GLIB_SRC_PATH)systime.cpp $(SYSTIME_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)systime.cpp

thelpers$(OBJ_EXT):	$(GLIB_SRC_PATH)thelpers.cpp $(THELPERS_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)thelpers.cpp

thrapiw$(OBJ_EXT):	$(GLIB_SRC_PATH)thrapiw.cpp $(THRAPIW_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)thrapiw.cpp

thrpool$(OBJ_EXT):	$(GLIB_SRC_PATH)thrpool.cpp $(THRPOOL_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)thrpool.cpp

ustring$(OBJ_EXT):	$(GLIB_SRC_PATH)ustring.cpp $(USTRING_DEP)
	$(CXX) $(COMPILE_ONLY) $(COMPILE_FLAGS) \
	$(GLIB_SRC_PATH)ustring.cpp
# --------------------------------------------------------------- 
#####################
#### End of File ####
#####################
