########################################################################
#
# Support for ESP boards (esp8266)
#
# You must install the ESP8266 board hardware support package from 
# to use this, then define ARDUINO_PACKAGE_DIR as the path to the root
# directory containing the support package.
#
# Installation instructions:
# https://arduino-esp8266.readthedocs.io/en/latest/installing.html
#
# Based on Sam.mk originally written by
# 2018 John Whittington @j_whittington
#
# Adapted for ESP8226 by
# Rainer Müller <raimue@codingfarm.de>
#
########################################################################

arduino_output =
# When output is not suppressed and we're in the top-level makefile,
# running for the first time (i.e., not after a restart after
# regenerating the dependency file), then output the configuration.
ifndef ARDUINO_QUIET
    ifeq ($(MAKE_RESTARTS),)
        ifeq ($(MAKELEVEL),0)
            arduino_output = $(info $(1))
        endif
    endif
endif

ifndef ARDMK_DIR
    ARDMK_DIR := $(realpath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
endif

# include Common.mk now we know where it is
ifndef COMMON_INCLUDED
    include $(ARDMK_DIR)/Common.mk
endif

ifndef ARDUINO_PACKAGE_DIR
    # attempt to find based on Linux, macOS and Windows default
    ARDUINO_PACKAGE_DIR := $(firstword \
        $(call dir_if_exists,$(HOME)/.arduino15/packages) \
        $(call dir_if_exists,$(ARDUINO_DIR)/packages) \
        $(call dir_if_exists,$(HOME)/Library/Arduino15/packages) \
        $(call dir_if_exists,$(USERPROFILE)/AppData/Local/Arduino15/packages) )
    $(call show_config_variable,ARDUINO_PACKAGE_DIR,[AUTODETECTED],(from DEFAULT))
else
    $(call show_config_variable,ARDUINO_PACKAGE_DIR,[USER])
endif

ifndef ARDMK_VENDOR
    ARDMK_VENDOR := esp8266
endif

ifndef ARCHITECTURE
    ARCHITECTURE := esp8266
endif

ifndef CORE_VER
    CORE_VER := $(wildcard $(ARDUINO_PACKAGE_DIR)/$(ARDMK_VENDOR)/hardware/$(ARCHITECTURE)/*)
    ifneq ($(CORE_VER),)
        CORE_VER := $(shell basename $(CORE_VER))
        $(call show_config_variable,CORE_VER,[AUTODETECTED],(from ARDUINO_PACKAGE_DIR))
    endif
else
    $(call show_config_variable,CORE_VER,[USER])
endif

# Arduino Settings (will get shown in Arduino.mk as computed)
ifndef ALTERNATE_CORE_PATH
    ifdef CORE_VER
        ALTERNATE_CORE_PATH = $(ARDUINO_PACKAGE_DIR)/$(ARDMK_VENDOR)/hardware/$(ARCHITECTURE)/$(CORE_VER)
    else
        ALTERNATE_CORE_PATH = $(ARDUINO_PACKAGE_DIR)/$(ARDMK_VENDOR)/hardware/$(ARCHITECTURE)
    endif
endif
ifndef ARDUINO_CORE_PATH
    ARDUINO_CORE_PATH   = $(ALTERNATE_CORE_PATH)/cores/arduino
endif
ifndef BOARDS_TXT
    BOARDS_TXT          = $(ALTERNATE_CORE_PATH)/boards.txt
endif

# Check boards file exists before continuing as parsing non-existant file can create problems
ifneq ($(findstring boards.txt, $(wildcard $(ALTERNATE_CORE_PATH)/*.txt)), boards.txt)
    echo $(error $(CORE_VER) Cannot find boards file $(BOARDS_TXT). Check ARDUINO_PACKAGE_DIR path: $(ARDUINO_PACKAGE_DIR) and board support installed)
endif

ifndef VARIANT
    VARIANT := $(call PARSE_BOARD,$(BOARD_TAG),menu.(chip|cpu).$(BOARD_SUB).build.variant)
    ifndef VARIANT
        VARIANT := $(call PARSE_BOARD,$(BOARD_TAG),build.variant)
    endif
endif

# grab any sources in the variant core path
ifndef ESP_CORE_PATH
    ESP_CORE_PATH := $(ALTERNATE_CORE_PATH)/variants/$(VARIANT)
endif
ESP_CORE_C_SRCS := $(wildcard $(ESP_CORE_PATH)/*.c)
ESP_CORE_CPP_SRCS := $(wildcard $(ESP_CORE_PATH)/*.cpp)
ESP_CORE_S_SRCS := $(wildcard $(ESP_CORE_PATH)/*.S)

# define plaform lib dir from Arduino ESP support
ifndef ARDUINO_PLATFORM_LIB_PATH
    ARDUINO_PLATFORM_LIB_PATH := $(ALTERNATE_CORE_PATH)/libraries
    $(call show_config_variable,ARDUINO_PLATFORM_LIB_PATH,[COMPUTED],(from ARDUINO_PACKAGE_DIR))
endif

########################################################################
# command names

TOOL_PREFIX ?= xtensa-lx106-elf

ifndef ESP_TOOLS_DIR
    ifndef ESP_TOOLS_VER
        ESP_TOOLS_VER := $(shell basename $(lastword $(wildcard $(ARDUINO_PACKAGE_DIR)/$(ARDMK_VENDOR)/tools/$(TOOL_PREFIX)-gcc/*)))
    endif
    ESP_TOOLS_DIR = $(ARDUINO_PACKAGE_DIR)/$(ARDMK_VENDOR)/tools/$(TOOL_PREFIX)-gcc/$(ESP_TOOLS_VER)
    ifdef ESP_TOOLS_DIR
        $(call show_config_variable,ESP_TOOLS_DIR,[COMPUTED],(from ARDUINO_PACKAGE_DIR))
    endif
else
    $(call show_config_variable,ESP_TOOLS_DIR,[USER])
endif

ifndef GDB_NAME
    GDB_NAME := $(call PARSE_BOARD,$(BOARD_TAG),build.command.gdb)
    ifndef GDB_NAME
        GDB_NAME := $(TOOL_PREFIX)-gdb
    else
        $(call show_config_variable,GDB_NAME,[COMPUTED])
    endif
endif

ifndef UPLOAD_TOOL
    UPLOAD_TOOL := $(call PARSE_BOARD,$(BOARD_TAG),upload.tool)
    ifndef UPLOAD_TOOL
    UPLOAD_TOOL := esptool
    else
        $(call show_config_variable,UPLOAD_TOOL,[COMPUTED])
    endif
endif

# processor stuff
ifndef MCU
    MCU := $(call PARSE_BOARD,$(BOARD_TAG),build.mcu)
endif

ifndef MCU_FLAG_NAME
    MCU_FLAG_NAME=mcpu
endif

########################################################################
# EXECUTABLES
# Define them here to use ARM_TOOLS_PATH and allow auto finding of AVR_TOOLS_PATH

AVR_TOOLS_DIR := $(ESP_TOOLS_DIR)

# Get extra define flags from boards.txt
EXFLAGS := $(shell echo $(call PARSE_BOARD,$(BOARD_TAG),build.extra_flags) | $(GREP_CMD) -oE '(-D)\w+')

CPPFLAGS += $(EXFLAGS)

ifndef SIZEFLAGS
    SIZEFLAGS += -B
endif

ifndef ESP_FLASHSIZE
    # Get supported flash sizes from all eesz.*.build.flash_size options
    ESP_FLASH_SIZES := $(shell sed -nE "s/^[ \t]*$(BOARD_TAG)\.menu\.eesz\.([^.]+)\.build\.flash_size=.*$$/\1/p" $(BOARDS_TXT))
    # Select first one as default
    ESP_FLASH_SIZE := $(firstword $(ESP_FLASH_SIZES))
    ESP_FLASHSIZE := $(call PARSE_BOARD,$(BOARD_TAG),menu.eesz.$(ESP_FLASH_SIZE).build.flash_size)

    ifndef LINKER_SCRIPTS 
        ESP_FLASH_LD := $(call PARSE_BOARD,$(BOARD_TAG),menu.eesz.$(ESP_FLASH_SIZE).build.flash_ld)
        ifneq (,$(strip $(ESP_FLASH_LD)))
            LINKER_SCRIPTS := "-T$(strip $(ESP_FLASH_LD))"
        endif
        $(call show_config_variable,LINKER_SCRIPTS,[BOARDS_TXT],(from *.eesz.$(ESP_FLASH_SIZE).build.flash_ld))
    else
        $(call show_config_variable,LINKER_SCRIPTS,[USER]))
    endif
endif

#ifndef PLATFORM_TXT
#    PLATFORM_TXT := $(ALTERNATE_CORE_PATH)/platform.txt
#endif
#
# TODO: $(call PARSE_BOARD,$(PLATFORM_TXT), ...

########################################################################
# automatially include Arduino.mk for the user

$(call show_separator)
$(call arduino_output,Arduino.mk Configuration:)
include $(ARDMK_DIR)/Arduino.mk
