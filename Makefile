# SPDX-FileCopyrightText: 2020 Efabless Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

# cannot commit files larger than 100 MB to GitHub
FILE_SIZE_LIMIT_MB = 100

# Commands to be used to compress/uncompress files
# they must operate **in place** (otherwise, modify the target to delete the
# intermediate file/archive)
COMPRESS ?= gzip -n --best
UNCOMPRESS ?= gzip -d
ARCHIVE_EXT ?= gz

# The following variables are to build static pattern rules

# Needed to rebuild archives that were previously split
SPLIT_FILES := $(shell find . -type f -name "*.$(ARCHIVE_EXT).00.split")
SPLIT_FILES_ARCHIVES := $(basename $(basename $(SPLIT_FILES)))
SPLIT_FILES_SOURCES := $(basename $(basename $(basename $(SPLIT_FILES))))

# Needed to uncompress the existing archives
ARCHIVES := $(shell find . -type f -not -path "*/signoff/*" -name "*.$(ARCHIVE_EXT)")
ARCHIVE_SOURCES := $(basename $(ARCHIVES))

# Needed to compress and split files/archives that are too large
LARGE_FILES := $(shell find ./gds -type f -name "*.gds")
LARGE_FILES += $(shell find . -type f -size +$(FILE_SIZE_LIMIT_MB)M \
	-not -path "*/signoff/*" \
	-not -path "*/.git/*" \
	-not -path "./gds/*" \
	-not -path "./tapeout/outputs/oas/*" \
	-not -path "*/openlane/*" \
	-not -name "*.$(ARCHIVE_EXT)")
LARGE_FILES_GZ := $(addsuffix .$(ARCHIVE_EXT), $(LARGE_FILES))
LARGE_FILES_GZ_SPLIT := $(addsuffix .$(ARCHIVE_EXT).00.split, $(LARGE_FILES))
# consider splitting existing archives
LARGE_FILES_GZ_SPLIT += $(addsuffix .00.split, $(ARCHIVES))

MCW_ROOT?=$(PWD)/mgmt_core_wrapper
MCW ?=LITEX_VEXRISCV
MPW_TAG ?= 2024.09.12-1

PYTHON_BIN ?= python3

# PDK switch varient
export PDK?=sky130A

# Install lite version of caravel, (1): caravel-lite, (0): caravel
MCW_LITE?=1

ifeq ($(MCW),LITEX_VEXRISCV)
	MCW_NAME := mcw-litex-vexriscv
	MCW_REPO ?= https://github.com/efabless/caravel_mgmt_soc_litex
	MCW_TAG ?= $(MPW_TAG)
else
	MCW_NAME := mcw-pico
	MCW_REPO ?= https://github.com/efabless/caravel_pico
	MCW_TAG ?= $(MPW_TAG)
endif

# Install caravel as submodule, (1): submodule, (0): clone
SUBMODULE?=0

# Caravel Root (Default: pwd)
# Need to be overwritten if running the makefile from UPRJ_ROOT,
# If caravel is sub-moduled in the user project, run export CARAVEL_ROOT=$(pwd)/caravel
CARAVEL_ROOT ?= $(shell pwd)

# User project root
UPRJ_ROOT ?= $(shell pwd)

# MANAGEMENT AREA ROOT
MGMT_AREA_ROOT ?= $(shell pwd)/mgmt_core_wrapper 

# Ensure commands which are piped through tee return the correct exit code
# to make
SHELL=/bin/bash -o pipefail

# PDK setup configs
THREADS ?= $(shell nproc)
STD_CELL_LIBRARY ?= sky130_fd_sc_hd
SPECIAL_VOLTAGE_LIBRARY ?= sky130_fd_sc_hvl
IO_LIBRARY ?= sky130_fd_io
PRIMITIVES_LIBRARY ?= sky130_fd_pr
OPEN_PDKS_COMMIT ?= 12df12e2e74145e31c5a13de02f9a1e176b56e67
# = 1.0.303

.DEFAULT_GOAL := ship
# We need portable GDS_FILE pointers...
.PHONY: ship
ship: check-env unsplit unsplit-caravel
	@echo "Running make ship in the foreground..."
	$(MAKE) -f $(CARAVEL_ROOT)/Makefile __ship
	@echo "Make ship completed." 2>&1 | tee -a ./signoff/build/make_ship.out

__ship:
	@echo "###############################################"
	@echo "Generating Caravel GDS (sources are in the 'gds' directory)"
	@sleep 1
#### Runs from the CARAVEL_ROOT mag directory 
	@echo "\
		random seed `$(CARAVEL_ROOT)/scripts/set_user_id.py -report`; \
		drc off; \
		crashbackups stop; \
		locking disable; \
		addpath hexdigits; \
		addpath $(MCW_ROOT)/mag; \
		addpath $(UPRJ_ROOT)/mag; \
		load user_project_wrapper; \
		property LEFview true; \
		property GDS_FILE $(UPRJ_ROOT)/gds/user_project_wrapper.gds; \
		property GDS_START 0; \
		load $(UPRJ_ROOT)/mag/user_id_programming; \
		load $(UPRJ_ROOT)/mag/user_id_textblock; \
		load $(CARAVEL_ROOT)/maglef/simple_por; \
		load $(UPRJ_ROOT)/mag/caravel_core -dereference; \
		load caravel -dereference; \
		select top cell; \
		expand; \
		cif *hier write disable; \
		cif *array write disable; \
		gds write $(UPRJ_ROOT)/gds/caravel.gds; \
		quit -noprompt;" > $(UPRJ_ROOT)/mag/mag2gds_caravel.tcl
### Runs from CARAVEL_ROOT
	@mkdir -p ./signoff/build
	#@cd $(CARAVEL_ROOT)/mag && PDKPATH=${PDK_ROOT}/$(PDK) MAGTYPE=mag magic -noc -dnull -rcfile ${PDK_ROOT}/$(PDK)/libs.tech/magic/$(PDK).magicrc $(UPRJ_ROOT)/mag/mag2gds_caravel.tcl 2>&1 | tee $(UPRJ_ROOT)/signoff/build/make_ship.out
	@cd $(CARAVEL_ROOT)/mag && PDKPATH=${PDK_ROOT}/$(PDK) MAGTYPE=mag magic -noc -dnull -rcfile ./.magicrc $(UPRJ_ROOT)/mag/mag2gds_caravel.tcl 2>&1 | tee $(UPRJ_ROOT)/signoff/build/make_ship.out
###	@rm $(UPRJ_ROOT)/mag/mag2gds_caravel.tcl

truck: check-env unsplit unsplit-caravel
	@echo "Running make truck in the foreground..."
	mkdir -p ./signoff
	mkdir -p ./build
	$(MAKE) -f $(CARAVEL_ROOT)/Makefile __truck
	@echo "Make truck completed." 2>&1 | tee -a ./signoff/build/make_truck.out

__truck: 
	@echo "###############################################"
	@echo "Generating Caravan GDS (sources are in the 'gds' directory)"
	@sleep 1
#### Runs from the CARAVEL_ROOT mag directory 
	@echo "\
		random seed `$(CARAVEL_ROOT)/scripts/set_user_id.py -report`; \
		drc off; \
		crashbackups stop; \
		locking disable; \
		addpath hexdigits; \
		addpath $(MCW_ROOT)/mag; \
		addpath $(UPRJ_ROOT)/mag; \
		load user_analog_project_wrapper; \
		property LEFview true; \
		property GDS_FILE $(UPRJ_ROOT)/gds/user_analog_project_wrapper.gds; \
		property GDS_START 0; \
		load $(UPRJ_ROOT)/mag/user_id_programming; \
		load $(UPRJ_ROOT)/mag/user_id_textblock; \
		load $(CARAVEL_ROOT)/maglef/simple_por; \
		load $(UPRJ_ROOT)/mag/caravan_core -dereference; \
		load caravan -dereference; \
		select top cell; \
		expand; \
		cif *hier write disable; \
		cif *array write disable; \
		gds write $(UPRJ_ROOT)/gds/caravan.gds; \
		quit -noprompt;" > $(UPRJ_ROOT)/mag/mag2gds_caravan.tcl
### Runs from CARAVEL_ROOT
	@mkdir -p ./signoff/build
	#@cd $(CARAVEL_ROOT)/mag && PDKPATH=${PDK_ROOT}/$(PDK) MAGTYPE=mag magic -noc -dnull -rcfile ${PDK_ROOT}/$(PDK)/libs.tech/magic/$(PDK).magicrc $(UPRJ_ROOT)/mag/mag2gds_caravan.tcl 2>&1 | tee $(UPRJ_ROOT)/signoff/build/make_truck.out
	@cd $(CARAVEL_ROOT)/mag && PDKPATH=${PDK_ROOT}/$(PDK) MAGTYPE=mag magic -noc -dnull -rcfile ./.magicrc $(UPRJ_ROOT)/mag/mag2gds_caravan.tcl 2>&1 | tee $(UPRJ_ROOT)/signoff/build/make_truck.out
###	@rm $(UPRJ_ROOT)/mag/mag2gds_caravan.tcl

.PHONY: openframe
openframe: check-env unsplit unsplit-caravel
	@echo "Running make openframe in the foreground..."
	$(MAKE) -f $(CARAVEL_ROOT)/Makefile __openframe
	@echo "Make openframe completed." 2>&1 | tee -a ./signoff/build/make_openframe.out

__openframe:
	@echo "###############################################"
	@echo "Generating Caravel GDS (sources are in the 'gds' directory)"
	@sleep 1
#### Runs from the CARAVEL_ROOT mag directory
	@echo "\
		drc off; \
		crashbackups stop; \
		locking disable; \
		addpath hexdigits; \
		addpath $(UPRJ_ROOT)/mag; \
		load openframe_project_wrapper; \
		property LEFview true; \
		property GDS_FILE $(UPRJ_ROOT)/gds/openframe_project_wrapper.gds; \
		property GDS_START 0; \
		load $(UPRJ_ROOT)/mag/user_id_programming; \
		load $(UPRJ_ROOT)/mag/user_id_textblock; \
		load $(CARAVEL_ROOT)/maglef/simple_por; \
		load caravel_openframe -dereference; \
		select top cell; \
		expand; \
		cif *hier write disable; \
		cif *array write disable; \
		gds write $(UPRJ_ROOT)/gds/caravel_openframe.gds; \
		quit -noprompt;" > $(UPRJ_ROOT)/mag/mag2gds_caravel_openframe.tcl
### Runs from CARAVEL_ROOT
	@mkdir -p ./signoff/build
	@cd $(CARAVEL_ROOT)/mag && PDKPATH=${PDK_ROOT}/$(PDK) MAGTYPE=mag magic -noc -dnull -rcfile ${PDK_ROOT}/$(PDK)/libs.tech/magic/$(PDK).magicrc $(UPRJ_ROOT)/mag/mag2gds_caravel_openframe.tcl 2>&1 | tee $(UPRJ_ROOT)/signoff/build/make_openframe.out

.PHONY: clean
clean:
	cd $(CARAVEL_ROOT)/verilog/dv/caravel/mgmt_soc/ && \
		$(MAKE) -j$(THREADS) clean
	cd $(CARAVEL_ROOT)/verilog/dv/wb_utests/ && \
		$(MAKE) -j$(THREADS) clean


.PHONY: verify
verify:
	cd $(CARAVEL_ROOT)/verilog/dv/caravel/mgmt_soc/ && \
		$(MAKE) -j$(THREADS) all
	cd $(CARAVEL_ROOT)/verilog/dv/wb_utests/ && \
		$(MAKE) -j$(THREADS) all



#####
$(LARGE_FILES_GZ): %.$(ARCHIVE_EXT): %
	@if ! [ $(suffix $<) = ".$(ARCHIVE_EXT)" ]; then\
		$(COMPRESS) $< > /dev/null &&\
		echo "$< -> $@";\
	fi

$(LARGE_FILES_GZ_SPLIT): %.$(ARCHIVE_EXT).00.split: %.$(ARCHIVE_EXT)
	@if [ -n "$$(find "$<" -prune -size +$(FILE_SIZE_LIMIT_MB)M)" ]; then\
		split $< -b $(FILE_SIZE_LIMIT_MB)M $<. -d &&\
		rm $< &&\
		for file in $$(ls $<.*); do mv "$$file" "$$file.split"; done &&\
		echo -n "$< -> $$(ls $<.*.split)" | tr '\n' ' ' && echo "";\
	fi

# This target compresses all files larger than $(FILE_SIZE_LIMIT_MB) MB
.PHONY: compress
compress: $(LARGE_FILES_GZ) $(LARGE_FILES_GZ_SPLIT)
	@echo "Files larger than $(FILE_SIZE_LIMIT_MB) MBytes are compressed!"



#####
$(ARCHIVE_SOURCES): %: %.$(ARCHIVE_EXT)
	@$(UNCOMPRESS) $<
	@echo "$< -> $@"

.SECONDEXPANSION:
$(SPLIT_FILES_SOURCES): %: $$(sort $$(wildcard %.$(ARCHIVE_EXT).*.split))
	@cat $? > $@.$(ARCHIVE_EXT)
	@rm $?
	@echo "$? -> $@.$(ARCHIVE_EXT)"
	@$(UNCOMPRESS) $@.$(ARCHIVE_EXT)
	@echo "$@.$(ARCHIVE_EXT) -> $@"


.PHONY: uncompress
uncompress: $(SPLIT_FILES_SOURCES) $(ARCHIVE_SOURCES)
	@echo "All files are uncompressed!"

# Needed for targets that are run from UPRJ_ROOT for which caravel isn't submoduled. 
.PHONY: uncompress-caravel
uncompress-caravel:
	cd $(CARAVEL_ROOT) && \
	$(MAKE) uncompress

.SECONDEXPANSION:
$(SPLIT_FILES_ARCHIVES): %: $$(sort $$(wildcard %.*.split))
	@cat $? > $@
	@rm $?
	@echo "$? -> $@"

.PHONY: unsplit
unsplit: $(SPLIT_FILES_ARCHIVES)
	@echo "All split files have been combined!"

# Needed for targets that are run from UPRJ_ROOT for which caravel isn't submoduled.
.PHONY: unsplit-caravel
unsplit-caravel:
	cd $(CARAVEL_ROOT) && \
	$(MAKE) unsplit

# Digital Wrapper
# verify that the wrapper was respected
.PHONY: xor-wrapper
xor-wrapper:
	@echo "The xor-wrapper target has been removed."
	@echo "This check is part of mpw_precheck."
	@exit 1

# Analog Wrapper
# verify that the wrapper was respected
.PHONY: xor-analog-wrapper
xor-analog-wrapper:
	@echo "The xor-analog-wrapper target has been removed."
	@echo "This check is part of mpw_precheck."
	@exit 1

OPENLANE_BLOCKS = $(shell cd openlane && find * -maxdepth 0 -type d)
# LVS
LVS_BLOCKS = $(foreach block, $(OPENLANE_BLOCKS), lvs-$(block))
$(LVS_BLOCKS): lvs-% : ./mag/%.mag ./verilog/gl/%.v
	@echo "The lvs-* targets have been renamed to lvs-mag-*"
	@exit 1

LVS_MAG_BLOCKS = $(foreach block, $(OPENLANE_BLOCKS), lvs-mag-$(block))
$(LVS_MAG_BLOCKS): lvs-mag-% : ./mag/%.mag ./verilog/gl/%.v
	@echo "Warning: the lvs-mag-* recipes may be out-of-date and are not officially supported."
	echo "Extracting $*"
	# Clear result directories 
	rm -rf ./mag/tmp
	mkdir -p ./mag/tmp
	rm -rf ./spi/lvs/tmp
	mkdir -p ./spi/lvs/tmp
	echo "addpath $(CARAVEL_ROOT)/mag/hexdigits;\
		addpath $(CARAVEL_ROOT)/mag/primitives;\
		addpath $(MCW_ROOT)/mag;\
		addpath $(CARAVEL_ROOT)/subcells/simple_por/mag;\
		addpath \$$PDKPATH/libs.ref/sky130_ml_xx_hd/mag;\
		load $* -dereference;\
		select top cell;\
		foreach cell [cellname list children] {\
			load \$$cell -dereference;\
			property LEFview TRUE;\
		};\
		load $* -dereference;\
		select top cell;\
		extract no all;\
		extract do local;\
		extract unique;\
		extract;\
		ext2spice lvs;\
		ext2spice $*.ext;\
		feedback save extract_$*.log;\
		exit;" > ./mag/extract_$*.tcl
	cd mag && \
		export MAGTYPE=maglef; \
		magic -rcfile ${PDK_ROOT}/$(PDK)/libs.tech/magic/$(PDK).magicrc -noc -dnull extract_$*.tcl < /dev/null
	mv ./mag/$*.spice ./spi/lvs
	rm ./mag/*.ext
	mv -f ./mag/extract_$*.tcl ./mag/tmp
	mv -f ./mag/extract_$*.log ./mag/tmp
	####
	sh $(CARAVEL_ROOT)/spi/lvs/run_lvs.sh ./spi/lvs/$*.spice ./verilog/gl/$*.v $*
	@echo ""
	python3 $(CARAVEL_ROOT)/scripts/count_lvs.py -f ./verilog/gl/$*.v_comp.json | tee ./spi/lvs/tmp/$*.lvs.summary.log
	mv -f ./verilog/gl/*.out ./spi/lvs/tmp 2> /dev/null || true
	mv -f ./verilog/gl/*.json ./spi/lvs/tmp 2> /dev/null || true
	mv -f ./verilog/gl/*.log ./spi/lvs/tmp 2> /dev/null || true
	@echo ""
	@echo "LVS: ./spi/lvs/$*.spice vs. ./verilog/gl/$*.v"
	@echo "Comparison result: ./spi/lvs/tmp/$*.v_comp.out"
	@awk '/^NET mismatches/,0' ./spi/lvs/tmp/$*.v_comp.out


LVS_GDS_BLOCKS = $(foreach block, $(OPENLANE_BLOCKS), lvs-gds-$(block))
$(LVS_GDS_BLOCKS): lvs-gds-% : ./gds/%.gds ./verilog/gl/%.v
	@echo "Warning: the lvs-gds-* recipes may be out-of-date and are not officially supported."
	echo "Extracting $*"
	# Clear result directories 
	rm -rf ./gds/tmp
	mkdir -p ./gds/tmp
	rm -rf ./spi/lvs/tmp
	mkdir -p ./spi/lvs/tmp
	echo "	gds flatglob \"*_example_*\";\
		gds flatten true;\
		gds read ./$*.gds;\
		load $* -dereference;\
		select top cell;\
		extract no all;\
		extract do local;\
		extract unique;\
		extract;\
		ext2spice lvs;\
		ext2spice $*.ext;\
		feedback save extract_$*.log;\
		exit;" > ./gds/extract_$*.tcl
	cd gds && \
		magic -rcfile ${PDK_ROOT}/$(PDK)/libs.tech/magic/$(PDK).magicrc -noc -dnull extract_$*.tcl < /dev/null
	mv ./gds/$*.spice ./spi/lvs
	rm ./gds/*.ext
	mv -f ./gds/extract_$*.tcl ./gds/tmp
	mv -f ./gds/extract_$*.log ./gds/tmp
	####
	MAGIC_EXT_USE_GDS=1 sh $(CARAVEL_ROOT)/spi/lvs/run_lvs.sh ./spi/lvs/$*.spice ./verilog/gl/$*.v $*
	@echo ""
	python3 $(CARAVEL_ROOT)/scripts/count_lvs.py -f ./verilog/gl/$*.v_comp.json | tee ./spi/lvs/tmp/$*.lvs.summary.log
	mv -f ./verilog/gl/*.out ./spi/lvs/tmp 2> /dev/null || true
	mv -f ./verilog/gl/*.json ./spi/lvs/tmp 2> /dev/null || true
	mv -f ./verilog/gl/*.log ./spi/lvs/tmp 2> /dev/null || true
	@echo ""
	@echo "LVS: ./spi/lvs/$*.spice vs. ./verilog/gl/$*.v"
	@echo "Comparison result: ./spi/lvs/tmp/$*.v_comp.out"
	@awk '/^NET mismatches/,0' ./spi/lvs/tmp/$*.v_comp.out


# connect-by-label is enabled here!
LVS_MAGLEF_BLOCKS = $(foreach block, $(OPENLANE_BLOCKS), lvs-maglef-$(block))
$(LVS_MAGLEF_BLOCKS): lvs-maglef-% : ./mag/%.mag ./verilog/gl/%.v
	@echo "Warning: the lvs-maglef-* recipes may be out-of-date and are not officially supported."
	echo "Extracting $*"
	mkdir -p ./maglef/tmp
	echo "load $* -dereference;\
		select top cell;\
		foreach cell [cellname list children] {\
			load \$$cell -dereference;\
			property LEFview TRUE;\
		};\
		load $* -dereference;\
		select top cell;\
		extract no all;\
		extract do local;\
		extract;\
		ext2spice lvs;\
		ext2spice $*.ext;\
		feedback save extract_$*.log;\
		exit;" > ./mag/extract_$*.tcl
	cd mag && export MAGTYPE=maglef; magic -noc -dnull extract_$*.tcl < /dev/null
	mv ./mag/$*.spice ./spi/lvs
	rm ./maglef/*.ext
	mv -f ./mag/extract_$*.tcl ./maglef/tmp
	mv -f ./mag/extract_$*.log ./maglef/tmp
	####
	mkdir -p ./spi/lvs/tmp
	sh $(CARAVEL_ROOT)/spi/lvs/run_lvs.sh ./spi/lvs/$*.spice ./verilog/gl/$*.v $*
	@echo ""
	python3 $(CARAVEL_ROOT)/scripts/count_lvs.py -f ./verilog/gl/$*.v_comp.json | tee ./spi/lvs/tmp/$*.maglef.lvs.summary.log
	mv -f ./verilog/gl/*.out ./spi/lvs/tmp 2> /dev/null || true
	mv -f ./verilog/gl/*.json ./spi/lvs/tmp 2> /dev/null || true
	mv -f ./verilog/gl/*.log ./spi/lvs/tmp 2> /dev/null || true
	@echo ""
	@echo "LVS: ./spi/lvs/$*.spice vs. ./verilog/gl/$*.v"
	@echo "Comparison result: ./spi/lvs/tmp/$*.v_comp.out"
	@awk '/^NET mismatches/,0' ./spi/lvs/tmp/$*.v_comp.out

# DRC
DRC_BLOCKS = $(foreach block, $(OPENLANE_BLOCKS), drc-$(block))
$(DRC_BLOCKS): drc-% : ./gds/%.gds
	echo "Running DRC on $*"
	mkdir -p ./gds/tmp
	cd gds && export DESIGN_IN_DRC=$* && export MAGTYPE=mag; magic -rcfile ${PDK_ROOT}/$(PDK)/libs.tech/magic/$(PDK).magicrc -noc -dnull $(CARAVEL_ROOT)/gds/drc_on_gds.tcl < /dev/null
	@echo "DRC result: ./gds/tmp/$*.drc"

# Antenna
ANTENNA_BLOCKS = $(foreach block, $(OPENLANE_BLOCKS), antenna-$(block))
$(ANTENNA_BLOCKS): antenna-% : ./gds/%.gds
	echo "Running Antenna Checks on $*"
	mkdir -p ./gds/tmp
	cd gds && export DESIGN_IN_ANTENNA=$* && export MAGTYPE=mag; magic -rcfile ${PDK_ROOT}/$(PDK)/libs.tech/magic/$(PDK).magicrc -noc -dnull $(CARAVEL_ROOT)/gds/antenna_on_gds.tcl < /dev/null 2>&1 | tee ./tmp/$*.antenna
	mv -f ./gds/*.ext ./gds/tmp/
	@echo "Antenna result: ./gds/tmp/$*.antenna"

# MAG2GDS
MAG2GDS_BLOCKS = $(foreach block, $(OPENLANE_BLOCKS), mag2gds-$(block))
$(MAG2GDS_BLOCKS): mag2gds-% : ./mag/%.mag unsplit unsplit-caravel
	echo "Converting mag file $* to GDS..."
	echo "addpath $(CARAVEL_ROOT)/mag/hexdigits;\
		addpath ${PDKPATH}/libs.ref/sky130_ml_xx_hd/mag;\
		addpath $(CARAVEL_ROOT)/mag/primitives;\
		drc off;\
		gds rescale false;\
		load $* -dereference;\
		select top cell;\
		expand;\
		gds write $*.gds;\
		exit;" > ./mag/mag2gds_$*.tcl
	cd ./mag && magic -rcfile ${PDK_ROOT}/$(PDK)/libs.tech/magic/$(PDK).magicrc -noc -dnull mag2gds_$*.tcl < /dev/null
	rm ./mag/mag2gds_$*.tcl
	mv -f ./mag/$*.gds ./gds/

# MAG2LEF 
MAG2LEF_BLOCKS = $(foreach block, $(OPENLANE_BLOCKS), mag2lef-$(block))
$(MAG2LEF_BLOCKS): mag2lef-% : ./mag/%.mag unsplit unsplit-caravel
	echo "Converting mag file $* to LEF..."
	echo "addpath $(CARAVEL_ROOT)/mag/hexdigits;\
		addpath ${PDKPATH}/libs.ref/sky130_ml_xx_hd/mag;\
		addpath $(CARAVEL_ROOT)/mag/primitives;\
		drc off;\
		load $*;\
		lef write $*.lef;\
		exit;" > ./mag/mag2lef_$*.tcl
	cd ./mag && magic -rcfile ${PDK_ROOT}/$(PDK)/libs.tech/magic/$(PDK).magicrc -noc -dnull mag2lef_$*.tcl < /dev/null
	rm ./mag/mag2lef_$*.tcl
	mv -f ./mag/$*.lef ./lef/

# MAG2DEF 
# BLOCKS = $(shell cd openlane && find * -maxdepth 0 -type d)
# MAG_BLOCKS = $(foreach block, $(OPENLANE_BLOCKS), mag2lef-$(block))
# $(MAG_BLOCKS): mag2lef-% : ./mag/%.mag unsplit unsplit-caravel
# 	echo "Converting mag file $* to DEF..."
# 	echo "addpath $(CARAVEL_ROOT)/mag/hexdigits;\
# 		addpath ${PDKPATH}/libs.ref/sky130_ml_xx_hd/mag;\
# 		addpath $(CARAVEL_ROOT)/mag/primitives;\
# 		drc off;\
# 		load $*;\
# 		lef write $*.lef;\
# 		exit;" > ./mag/mag2lef_$*.tcl
# 	cd ./mag && magic -rcfile ${PDK_ROOT}/$(PDK)/libs.tech/magic/$(PDK).magicrc -noc -dnull mag2lef_$*.tcl < /dev/null
# 	rm ./mag/mag2lef_$*.tcl
# 	mv -f ./mag/$*.lef ./lef/

.PHONY: help
help:
	@$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$'

# RCX Extraction
RCX_BLOCKS = $(foreach block, $(OPENLANE_BLOCKS), rcx-$(block))
OPENLANE_IMAGE_NAME=efabless/openlane:2021.11.25_01.26.14
$(RCX_BLOCKS): rcx-% : ./def/%.def 
	echo "Running RC Extraction on $*"
	mkdir -p ./def/tmp 
	# merge techlef and standard cell lef files
	python3 $(OPENLANE_ROOT)/scripts/mergeLef.py -i $(PDK_ROOT)/$(PDK)/libs.ref/$(STD_CELL_LIBRARY)/techlef/$(STD_CELL_LIBRARY).tlef $(PDK_ROOT)/$(PDK)/libs.ref/$(STD_CELL_LIBRARY)/lef/*.lef $(PDK_ROOT)/$(PDK)/libs.ref/$(SPECIAL_VOLTAGE_LIBRARY)/techlef/$(SPECIAL_VOLTAGE_LIBRARY).tlef $(PDK_ROOT)/$(PDK)/libs.ref/$(SPECIAL_VOLTAGE_LIBRARY)/lef/*.lef $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lef/*.lef -o ./def/tmp/merged.lef
	echo "\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(STD_CELL_LIBRARY)/lib/$(STD_CELL_LIBRARY)__tt_025C_1v80.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(SPECIAL_VOLTAGE_LIBRARY)/lib/$(SPECIAL_VOLTAGE_LIBRARY)__tt_025C_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(SPECIAL_VOLTAGE_LIBRARY)/lib/$(SPECIAL_VOLTAGE_LIBRARY)__tt_025C_3v30_lv1v80.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/sky130_sram_macros/lib/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_fd_io__top_gpiov2_tt_tt_025C_1v80_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_fd_io__top_ground_hvc_wpad_tt_025C_1v80_3v30_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_fd_io__top_ground_lvc_wpad_tt_025C_1v80_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_fd_io__top_ground_lvc_wpad_tt_100C_1v80_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_fd_io__top_power_lvc_wpad_tt_025C_1v80_3v30_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_fd_io__top_xres4v2_tt_tt_025C_1v80_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__gpiov2_pad_tt_tt_025C_1v80_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__vccd_lvc_clamped_pad_tt_025C_1v80_3v30_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__vdda_hvc_clamped_pad_tt_025C_1v80_3v30_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__vssa_hvc_clamped_pad_tt_025C_1v80_3v30_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__vssd_lvc_clamped3_pad_tt_025C_1v80_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__vccd_lvc_clamped3_pad_tt_025C_1v80_3v30_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__vssd_lvc_clamped_pad_tt_025C_1v80_3v30.lib;\
		set std_cell_lef ./def/tmp/merged.lef;\
		set sram_lef $(PDK_ROOT)/$(PDK)/libs.ref/sky130_sram_macros/lef/sky130_sram_2kbyte_1rw1r_32x512_8.lef;\
		if {[catch {read_lef \$$std_cell_lef} errmsg]} {\
    			puts stderr \$$errmsg;\
    			exit 1;\
		};\
		if {[catch {read_lef \$$sram_lef} errmsg]} {\
    			puts stderr \$$errmsg;\
    			exit 1;\
		};\
		foreach lef_file [glob ./lef/*.lef] {\
			if {[catch {read_lef \$$lef_file} errmsg]} {\
    			puts stderr \$$errmsg;\
    			exit 1;\
			}\
		};\
		if {[catch {read_def -order_wires ./def/$*.def} errmsg]} {\
			puts stderr \$$errmsg;\
			exit 1;\
		};\
		read_sdc -echo ./sdc/$*.sdc;\
		set_propagated_clock [all_clocks];\
		set rc_values \"mcon 9.249146E-3,via 4.5E-3,via2 3.368786E-3,via3 0.376635E-3,via4 0.00580E-3\";\
		set l_rc \"li1 1.499e-04 7.176e-02,met1 1.449e-04 8.929e-04,met2 1.331e-04 8.929e-04,met3 1.464e-04 1.567e-04,met4 1.297e-04 1.567e-04,met5 1.501e-04 1.781e-05\";\
		set layers_rc [split \$$l_rc ","];\
		foreach layer_rc \$$layers_rc {\
			set layer_name [lindex \$$layer_rc 0];\
			set capacitance [lindex \$$layer_rc 1];\
			set resistance [lindex \$$layer_rc 2];\
			set_layer_rc -layer \$$layer_name -capacitance \$$capacitance -resistance \$$resistance;\
		};\
		set vias_rc [split \$$rc_values ","];\
    	foreach via_rc \$$vias_rc {\
        		set layer_name [lindex \$$via_rc 0];\
        		set resistance [lindex \$$via_rc 1];\
       			set_layer_rc -via \$$layer_name -resistance \$$resistance;\
    	};\
		set_wire_rc -signal -layer met2;\
		set_wire_rc -clock -layer met5;\
		define_process_corner -ext_model_index 0 X;\
		extract_parasitics -ext_model_file ${PDK_ROOT}/$(PDK)/libs.tech/openlane/rcx_rules.info -corner_cnt 1 -max_res 50 -coupling_threshold 0.1 -cc_model 10 -context_depth 5;\
		write_spef ./spef/$*.spef" > ./def/tmp/rcx_$*.tcl
## Generate Spef file
	docker run -it -v $(OPENLANE_ROOT):/openlane -v $(PDK_ROOT):$(PDK_ROOT) -v $(PWD):/caravel -e PDK_ROOT=$(PDK_ROOT) -u $(shell id -u $(USER)):$(shell id -g $(USER)) $(OPENLANE_IMAGE_NAME) \
	sh -c " cd /caravel; openroad -exit ./def/tmp/rcx_$*.tcl |& tee ./def/tmp/rcx_$*.log" 
## Run OpenSTA
	echo "\
		set std_cell_lef ./def/tmp/merged.lef;\
		set sram_lef $(PDK_ROOT)/$(PDK)/libs.ref/sky130_sram_macros/lef/sky130_sram_2kbyte_1rw1r_32x512_8.lef;\
		if {[catch {read_lef \$$std_cell_lef} errmsg]} {\
    			puts stderr \$$errmsg;\
    			exit 1;\
		};\
		if {[catch {read_lef \$$sram_lef} errmsg]} {\
    			puts stderr \$$errmsg;\
    			exit 1;\
		};\
		foreach lef_file [glob ./lef/*.lef] {\
			if {[catch {read_lef \$$lef_file} errmsg]} {\
    			puts stderr \$$errmsg;\
    			exit 1;\
			}\
		};\
		set_cmd_units -time ns -capacitance pF -current mA -voltage V -resistance kOhm -distance um;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(STD_CELL_LIBRARY)/lib/$(STD_CELL_LIBRARY)__tt_025C_1v80.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(SPECIAL_VOLTAGE_LIBRARY)/lib/$(SPECIAL_VOLTAGE_LIBRARY)__tt_025C_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(SPECIAL_VOLTAGE_LIBRARY)/lib/sky130_fd_sc_hvl__tt_025C_3v30_lv1v80.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/sky130_sram_macros/lib/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_fd_io__top_gpiov2_tt_tt_025C_1v80_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_fd_io__top_ground_hvc_wpad_tt_025C_1v80_3v30_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_fd_io__top_ground_lvc_wpad_tt_025C_1v80_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_fd_io__top_ground_lvc_wpad_tt_100C_1v80_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_fd_io__top_power_lvc_wpad_tt_025C_1v80_3v30_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_fd_io__top_xres4v2_tt_tt_025C_1v80_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__gpiov2_pad_tt_tt_025C_1v80_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__vccd_lvc_clamped_pad_tt_025C_1v80_3v30_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__vdda_hvc_clamped_pad_tt_025C_1v80_3v30_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__vssa_hvc_clamped_pad_tt_025C_1v80_3v30_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__vssd_lvc_clamped3_pad_tt_025C_1v80_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__vccd_lvc_clamped3_pad_tt_025C_1v80_3v30_3v30.lib;\
		read_liberty $(PDK_ROOT)/$(PDK)/libs.ref/$(IO_LIBRARY)/lib/sky130_ef_io__vssd_lvc_clamped_pad_tt_025C_1v80_3v30.lib;\
		read_verilog ./verilog/gl/$*.v;\
		link_design $*;\
		read_spef ./spef/$*.spef;\
		read_sdc -echo ./sdc/$*.sdc;\
		write_sdf ./sdf/$*.sdf -divider . -include_typ;\
		report_checks -fields {capacitance slew input_pins nets fanout} -path_delay min_max -group_count 5;\
		report_check_types -max_slew -max_capacitance -max_fanout -violators;\
		report_checks -to [all_outputs] -group_count 1000;\
		" > ./def/tmp/sta_$*.tcl 
	docker run -it -v $(OPENLANE_ROOT):/openlane -v $(PDK_ROOT):$(PDK_ROOT) -v $(PWD):/caravel -e PDK_ROOT=$(PDK_ROOT) -u $(shell id -u $(USER)):$(shell id -g $(USER)) $(OPENLANE_IMAGE_NAME) \
	sh -c "cd /caravel; openroad -exit ./def/tmp/sta_$*.tcl |& tee ./def/tmp/sta_$*.log" 


.PHONY: caravel_timing_typ caravel_timing_typ caravel_timing_slow
caravel_timing_typ:
	@echo "The caravel_timing_typ: target has been removed."
	@echo "Please use the caravel-sta target in the caravel_user_project/Makefile"
	@exit 1

caravel_timing_slow:
	@echo "The caravel_timing_slow: target has been removed."
	@echo "Please use the caravel-sta target in the caravel_user_project/Makefile"
	@exit 1

caravel_timing_fast:
	@echo "The caravel_timing_fast: target has been removed."
	@echo "Please use the caravel-sta target in the caravel_user_project/Makefile"
	@exit 1

###########################################################################
.PHONY: generate_fill
generate_fill: check-env check-uid check-project unsplit unsplit-caravel
	@echo "Running generate_fill in the foreground..."
	$(MAKE) -f $(CARAVEL_ROOT)/Makefile __generate_fill
	@echo "Generate fill completed." 2>&1 | tee -a ./signoff/build/generate_fill.out

__generate_fill:
	@mkdir -p ./signoff/build
	@cp -r $(CARAVEL_ROOT)/mag/.magicrc $(shell pwd)/mag
	python3 $(CARAVEL_ROOT)/scripts/generate_fill.py $(USER_ID) $(PROJECT) $(shell pwd) -dist 2>&1 | tee ./signoff/build/generate_fill.out
	#python3 $(CARAVEL_ROOT)/scripts/generate_fill.py $(USER_ID) $(PROJECT) $(shell pwd) -keep 2>&1 | tee ./signoff/build/generate_fill.out


.PHONY: final
final: check-env check-uid check-project unsplit unsplit-caravel
	$(MAKE) -f $(CARAVEL_ROOT)/Makefile __final
	@echo "Final build completed." 2>&1 | tee -a ./signoff/build/final_build.out

__final:
	python3 $(CARAVEL_ROOT)/scripts/compositor.py $(USER_ID) $(PROJECT) $(shell pwd) $(CARAVEL_ROOT)/mag $(shell pwd)/gds $(MCW_ROOT) -keep 2>&1 | tee ./signoff/build/final_build.out
	#mv $(CARAVEL_ROOT)/mag/caravel_$(USER_ID).mag ./mag/
	@rm -rf ./mag/tmp

.PHONY: set_user_id
set_user_id: check-env check-uid
	$(MAKE) -f $(CARAVEL_ROOT)/Makefile __set_user_id
	@echo "Set user ID completed." 2>&1 | tee -a ./signoff/build/set_user_id.out

__set_user_id: 
	mkdir -p ./signoff/build
	# Update info.yaml
	# sed -r "s/^(\s*project_id\s*:\s*).*/\1${USER_ID}/" -i info.yaml
	cp $(CARAVEL_ROOT)/mag/user_id_programming.mag ./mag/user_id_programming.mag
	cp $(CARAVEL_ROOT)/mag/user_id_textblock.mag ./mag/user_id_textblock.mag
	cp $(CARAVEL_ROOT)/verilog/rtl/caravel_core.v ./verilog/rtl/caravel_core.v
	cp $(CARAVEL_ROOT)/verilog/gl/user_id_programming.v ./verilog/gl/user_id_programming.v
	python3 $(CARAVEL_ROOT)/scripts/set_user_id.py $(USER_ID) $(shell pwd) 2>&1 | tee ./signoff/build/set_user_id.out

.PHONY: gpio_defaults
gpio_defaults: check-env
	$(MAKE) -f $(CARAVEL_ROOT)/Makefile __gpio_defaults
	@echo "GPIO defaults completed." 2>&1 | tee -a ./signoff/build/__gpio_defaults.out

__gpio_defaults:
	mkdir -p ./signoff/build
	mkdir -p ./verilog/gl
	python3 $(CARAVEL_ROOT)/scripts/gen_gpio_defaults.py $(shell pwd) 2>&1 | tee ./signoff/build/gpio_defaults.out

.PHONY: update_caravel
update_caravel:
	@echo "The update_caravel target has been removed."
	@exit 1

###########################################################################

# Install Mgmt Core Wrapper
.PHONY: install_mcw
install_mcw:
	if [ -d "$(MCW_ROOT)" ]; then \
		echo "Deleting existing $(MCW_ROOT)" && \
		rm -rf $(MCW_ROOT) && sleep 2;\
	fi
ifeq ($(SUBMODULE),1)
	@echo "Installing $(MCW_NAME) as a submodule.."
# Convert MCW_ROOT to relative path because .gitmodules doesn't accept '/'
	$(eval MCW_PATH := $(shell realpath --relative-to=$(shell pwd) $(MCW_ROOT)))
	@if [ ! -d $(MCW_ROOT) ]; then git submodule add --name $(MCW_NAME) $(MCW_REPO) $(MCW_PATH); fi
	@git submodule update --init
	@cd $(MCW_ROOT); git checkout $(MCW_TAG)
	$(MAKE) simlink
else
	@echo "Installing $(MCW_NAME).."
	@git clone -b $(MCW_TAG) $(MCW_REPO) $(MCW_ROOT) --depth=1
endif


# Update Mgmt Core Wrapper
.PHONY: update_mcw
update_mcw: check-mcw
ifeq ($(SUBMODULE),1)
	@git submodule update --init --recursive
	cd $(MCW_ROOT) && \
	git checkout $(MCW_TAG) && \
	git pull
else
	cd $(MCW_ROOT)/ && \
		git checkout $(MCW_TAG) && \
		git pull
endif

# Uninstall Mgmt Core Wrapper
.PHONY: uninstall_mcw
uninstall_mcw:
ifeq ($(SUBMODULE),1)
	git config -f .gitmodules --remove-section "submodule.$(MCW_NAME)"
	git add .gitmodules
	git submodule deinit -f $(MCW_ROOT)
	git rm --cached $(MCW_ROOT)
	rm -rf .git/modules/$(MCW_NAME)
	rm -rf $(MCW_ROOT)
else
	rm -rf $(MCW_ROOT)/*
endif


###########################################################################
.PHONY: pdk pdk-with-sram
pdk-with-sram: pdk
pdk: check-env pdk-with-volare

.PHONY: pdk-with-volare
pdk-with-volare: check-env venv/manifest.txt
	./venv/bin/volare enable ${OPEN_PDKS_COMMIT}

.PHONY: install-volare
install-volare:
	@echo "The install-volare target has been removed."
	@echo "To delete and reinstall: make -B venv/manifest.txt"
	@exit 1

.PHONY: clean-pdk
clean-pdk:
	rm -rf $(PDK_ROOT)

.PHONY: skywater-pdk
skywater-pdk:
	@echo "The skywater-pdk target has been removed."
	@echo "To install the pdk with volare: make pdk-with-volare"
	@exit 1

### OPEN_PDKS
.PHONY: open-pdks
open-pdks:
	@echo "The open-pdks target has been removed."
	@echo "To install the pdk with volare: make pdk-with-volare"
	@exit 1

.PHONY: sky130
sky130:
	@echo "The sky130 target has been removed."
	@echo "To install the pdk with volare: make pdk-with-volare"
	@exit 1

.PHONY: gen-sources
gen-sources:
	@echo "The gen-sources target has been removed."
	@echo "The $(PDK_ROOT)/$(PDK)/SOURCES file is created by volare."
	@exit 1

# Make README.rst
README.rst: README.src.rst docs/source/getting-started.rst docs/source/tool-versioning.rst openlane/README.src.rst docs/source/caravel-with-openlane.rst Makefile ./venv/manifest.txt
	rm -f README.rst openlane/README.rst && \
		./venv/bin/rst_include include README.src.rst - | \
			sed \
				-e's@\.\/\_static@\/docs\/source\/\_static@g' \
				-e's@:doc:`tool-versioning`@`tool-versioning.rst <./docs/source/tool-versioning.rst>`__@g' \
				-e's@.. note::@**NOTE:**@g' \
				-e's@.. warning::@**WARNING:**@g' \
				> README.rst && \
		./venv/bin/rst_include include openlane/README.src.rst - | \
			sed \
				-e's@https://github.com/efabless/caravel/blob/master/verilog@../verilog@g' \
				-e's@:ref:`getting-started`@`README.rst <../README.rst>`__@g' \
				-e's@https://github.com/efabless/caravel/blob/master/openlane/@./@g' \
				-e's@.. note::@**NOTE:**@g' \
				-e's@.. warning::@**WARNING:**@g' \
				> openlane/README.rst
				
venv/manifest.txt: $(CARAVEL_ROOT)/requirements.txt
	$(MAKE) check-python
	rm -rf ./venv
	$(PYTHON_BIN) -m venv ./venv
	./venv/bin/python3 -m pip install --upgrade --no-cache-dir pip
	./venv/bin/python3 -m pip install --upgrade --no-cache-dir -r $(CARAVEL_ROOT)/requirements.txt
	./venv/bin/python3 -m pip freeze > $@

###########################################################################
	
.PHONY: manifest
manifest: mag/ maglef/ verilog/rtl/ Makefile
	touch manifest && \
	find verilog/rtl/* -type f ! -name "caravel_netlists.v" ! -name "user_*.v" ! -name "README" ! -name "defines.v" -exec shasum {} \; > manifest && \
	shasum scripts/set_user_id.py scripts/generate_fill.py scripts/compositor.py >> manifest
	# since the order of files returned by find is indeterminate, sort the final output by filename
	LC_ALL=C sort -k2,2 -o manifest manifest
# shasum lef/user_project_wrapper_empty.lef >> manifest
# find maglef/*.mag -type f ! -name "user_project_wrapper.mag" -exec shasum {} \; >> manifest && \
# shasum mag/caravel.mag mag/.magicrc >> manifest

.PHONY: master_manifest
master_manifest:
	# to get the shasums of compressed files, first create a list of the compressed files
	# uncompress them, take the shasums, and then recompress the files
	shopt -s nullglob; \
	ls verilog/rtl/*.$(ARCHIVE_EXT) verilog/gl/*.$(ARCHIVE_EXT) lef/*.lef.$(ARCHIVE_EXT) def/*.def.$(ARCHIVE_EXT) mag/*.mag.$(ARCHIVE_EXT) \
		maglef/*.mag.$(ARCHIVE_EXT) spi/lvs/*.spice.$(ARCHIVE_EXT) gds/*.gds.$(ARCHIVE_EXT) | \
	sed 's/\.'$(ARCHIVE_EXT)'\>//g' > manifest.compressed.list && sleep 2
	find verilog/rtl -type f -not -name "*.$(ARCHIVE_EXT)" -exec shasum {} \; > master_manifest && \
	find verilog/gl -type f -not -name "*.$(ARCHIVE_EXT)" -exec shasum {} \; >> master_manifest && \
	shasum scripts/set_user_id.py scripts/generate_fill.py scripts/compositor.py >> master_manifest && \
	find lef -name "*.lef" -type f -exec shasum {} \; >> master_manifest && \
	find def -name "*.def" -type f -exec shasum {} \; >> master_manifest && \
	find mag -name "*.mag" -type f  -exec shasum {} \; >> master_manifest && \
	find maglef -name "*.mag" -type f -exec shasum {} \; >> master_manifest && \
	find spi/lvs -name "*.spice" -type f -exec shasum {} \; >> master_manifest && \
	find gds -name "*.gds" -type f -exec shasum {} \; >> master_manifest 
	# since file compression options may be different, do not uncompress and recompress
	for file in $$(cat manifest.compressed.list); do \
		echo "$$( $(UNCOMPRESS) -c $$file | shasum | awk '{print $$1}' )  $$file" >> master_manifest; \
	done
	# since the order of files returned by find is indeterminate, sort the final output by filename
	LC_ALL=C sort -k2,2 -o master_manifest master_manifest
	rm -rf manifest.compressed.list
	
.PHONY: check-env
check-env:
ifndef PDK_ROOT
	$(error PDK_ROOT is undefined, please export it before running make)
endif

check-uid:
ifndef USER_ID
	$(error USER_ID is undefined, please export it before running make set_user_id)
else 
	@echo USER_ID is set to $(USER_ID)
endif

check-project:
ifndef PROJECT
	$(error PROJECT is undefined, please export it before running make generate_fill or make final)
else
	@echo PROJECT is set to $(PROJECT)
endif

check-mcw:
	@if [ ! -d "$(MCW_ROOT)" ]; then \
		echo "MCW Root: "$(MCW_ROOT)" doesn't exists, please export the correct path before running make. "; \
		exit 1; \
	fi
	
check-python:
	@if ! command -v $(PYTHON_BIN) > /dev/null; then\
		echo "Python 3 binary '$(PYTHON_BIN)' not found.";\
		exit 1;\
	fi
	@$(PYTHON_BIN) -c "import sys; assert sys.version_info >= (3, 6), 'Python version less than 3.6'"
	@echo "Python >=3.6 found."

.PHONY: check-gpio-id
check-gpio-id: check-uid
	$(CARAVEL_ROOT)/scripts/run_gpio-id_check caravel_$$USER_ID tapeout/outputs/oas/caravel_$$USER_ID.oas*

.PHONY: clean-openlane
clean-openlane:
	rm -rf $(OPENLANE_ROOT)

