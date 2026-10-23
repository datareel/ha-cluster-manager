#######################
#### Start of File ####
#######################
# --------------------------------------------------------------- 
# Makefile Contents: make file to build the DataReel library subset
# used by the DRCM server
# C/C++ Compiler Used: GNU, Intel, Cray
# Produced By: DataReel Software Development Team
# File Creation Date: 05/25/2001
# Date Last Modified: 10/23/2026
# --------------------------------------------------------------- 
# Setup my path to the gxcode library
GCODE_LIB_DIR = ..

include ../env/linux.env

# Define a name for the static library
PROJECT = libdatareel

# Build dependency rules
# ===============================================================
include ../env/glibdeps.mak
# ===============================================================

# Compile the object files and build the library
# ===============================================================
all: CREATE_ALL_LIBS

include ../env/glibobjs.mak

COMPILE_FLAGS := $(COMPILE_FLAGS) $(LIBCOMPILE_FLAGS)

# Low-level file I/O components
GLIB_FILE_OBJECTS = dfileb$(OBJ_EXT) \
	futils$(OBJ_EXT) \
	gxdfp64$(OBJ_EXT) \
	gxdfptr$(OBJ_EXT)

# Socket library components
GLIB_SOCKET_OBJECTS = gxsocket$(OBJ_EXT)

# Thread library components
GLIB_THREAD_OBJECTS = gthreadt$(OBJ_EXT) \
	gxmutex$(OBJ_EXT) \
	thelpers$(OBJ_EXT) \
	thrapiw$(OBJ_EXT) \
	gxthread$(OBJ_EXT) \
	gxcond$(OBJ_EXT) \
	thrpool$(OBJ_EXT)

# General purpose library components
GLIB_GP_OBJECTS = logfile$(OBJ_EXT) \
	strutil$(OBJ_EXT) \
	systime$(OBJ_EXT) \
	ustring$(OBJ_EXT) 

# Set the library components to compile here
GLIB_OBJECTS = $(GLIB_FILE_OBJECTS) \
	$(GLIB_SOCKET_OBJECTS) \
	$(GLIB_THREAD_OBJECTS) \
	$(GLIB_GP_OBJECTS)

# Add additional object files here
OBJECTS = $(GLIB_OBJECTS) 

CREATE_ALL_LIBS:	$(OBJECTS)
	echo Building static libary
	$(LIBUTIL) $(LIBUTIL_FLAGS) ./$(PROJECT)$(LIB_EXT) $(OBJECTS)
	$(RANLIB_UTIL) ./$(PROJECT)$(LIB_EXT)

	echo Building shared library
	$(SHARED_LIBUTIL) $(SHAREDLIBUTIL_FLAGS) \
	-o ./$(PROJECT)$(SHAREDLIB_EXT) $(OBJECTS) $(LINKER_FLAGS)
# ===============================================================

# install the library files
# ===============================================================
install:
	echo Removing any old library files
	rm -f $(LIB_INSTALL_DIR)/$(PROJECT)$(LIB_EXT)
	rm -f $(LIB_INSTALL_DIR)/$(PROJECT)$(DLIB_EXT)
	rm -f $(LIB_INSTALL_DIR)/$(PROJECT)$(SHAREDLIB_EXT)

	echo Copying library files
	cp $(PROJECT)$(LIB_EXT) $(LIB_INSTALL_DIR)/$(PROJECT)$(LIB_EXT)
	cp $(PROJECT)$(SHAREDLIB_EXT) \
	$(LIB_INSTALL_DIR)/$(PROJECT)$(SHAREDLIB_EXT)

	echo Creating symbolic links
	$(LN_S) $(LIB_INSTALL_DIR)/$(PROJECT)$(SHAREDLIB_EXT) \
	$(LIB_INSTALL_DIR)/$(PROJECT)$(DLIB_EXT)

# Remove object files and libary files from current directory 
# ===============================================================
clean:
	echo Removing all OBJECT files from working directory...
	rm -f *.o 

	echo Removing static and shared libary files
	rm -f $(PROJECT)$(LIB_EXT)
	rm -f $(PROJECT)$(SHAREDLIB_EXT)

clean_lib:
	rm -fv ../lib/libdatareel.a
	rm -fv ../lib/libdatareel.so
	rm -fv ../lib/libdatareel.so.5.0
# --------------------------------------------------------------- 
#####################
#### End of File ####
#####################
