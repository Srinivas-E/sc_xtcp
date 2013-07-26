# The TARGET variable determines what target system the application is
# compiled for. It either refers to an XN file in the source directories
# or a valid argument for the --target option when compiling
TARGET = SLICEKIT-L16

# The APP_NAME variable determines the name of the final .xe file. It should
# not include the .xe postfix. If left blank the name will default to
# the project name
APP_NAME = 

# The USED_MODULES variable lists other module used by the application.
USED_MODULES = module_ethernet_board_support module_logging module_random module_xassert module_xtcp

COMMA = ,
ifneq ($(STATIC_IP),)
STATIC_IP_FLAGS = -DSTATIC_IP={$(subst .,$(COMMA),$(STATIC_IP))}
else
$(warning This makefile requires STATIC_IP (e.g 169.254.196.178) to be supplied as build argument)
endif

ifneq ($(CONTROLLER_IP),)
CONTROLLER_IP_FLAGS = -DCONTROLLER_IP={$(subst .,$(COMMA),$(CONTROLLER_IP))}
else
$(warning This makefile requires CONTROLLER_IP (e.g 169.254.196.175) to be supplied as build argument)
endif

# The flags passed to xcc when building the application
# You can also set the following to override flags for a particular language:
# XCC_XC_FLAGS, XCC_C_FLAGS, XCC_ASM_FLAGS, XCC_CPP_FLAGS
# If the variable XCC_MAP_FLAGS is set it overrides the flags passed to
# xcc for the final link (mapping) stage.
XCC_FLAGS_Debug = -O0 -g -fxscope $(STATIC_IP_FLAGS) $(CONTROLLER_IP_FLAGS)
XCC_FLAGS_Release = -O2 -g -fxscope $(STATIC_IP_FLAGS) $(CONTROLLER_IP_FLAGS)

# The VERBOSE variable, if set to 1, enables verbose output from the make system.
VERBOSE = 0

XMOS_MAKE_PATH ?= ../..
-include $(XMOS_MAKE_PATH)/xcommon/module_xcommon/build/Makefile.common
