
PROJECT = fpga/sha1
SOURCES= src/wrapper_sha1.v src/sha1_wb.v
ICEBREAKER_DEVICE = up5k
ICEBREAKER_PIN_DEF = fpga/icebreaker.pcf
ICEBREAKER_PACKAGE = sg48
SEED = 1
MULTI_PROJECT_DIR ?= $(PWD)/../multi_project_tools
PRECHECK = $(PWD)/../open_mpw_precheck
GCC_PATH ?= /opt/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-linux-centos6/bin
GCC_PREFIX ?= riscv64-unknown-elf

CHIP_VIS_DIR ?= $(PWD)/../sky130-chip-vis
PDK = sky130_fd_sc_hd
GL = gds/wrapper_sha1.lvs.powered.v
GDS = gds/wrapper_sha1.gds
VCD = wrapper.vcd
CELLS = $(PDK_ROOT)/sky130A/libs.ref/$(PDK)/verilog/$(PDK).v

# COCOTB variables
export COCOTB_REDUCED_LOG_FMT=1

all: test_sha1 test_wb_logic test_wrapper prove_sha1

tests: test_sha1 test_wb_logic test_wrapper test_gds test_lvs_wrapper

test_gds: gds/wrapper_sha1.lvs.powered.v
	$(MAKE) -C gds

.PHONY: run_gds
run_gds:
	docker run -it \
		-v $(CURDIR):/work \
		-v $(OPENLANE_ROOT):/openLANE_flow \
		-v $(PDK_ROOT):$(PDK_ROOT) \
		-v $(PDK_PATH):$(PDK_PATH) \
		-v $(CURDIR):/out \
		-e PDK_ROOT=$(PDK_ROOT) \
		-e PDK_PATH=$(PDK_PATH) \
		-u $(shell id -u $$USER):$(shell id -g $$USER) \
		efabless/openlane:v0.15 \
		/bin/bash -c "./flow.tcl -overwrite -design /work/ -run_path /out/ -tag done"
	! find done -name *.log | xargs grep ERROR
	cp -f done/results/lvs/wrapper_sha1.lvs.powered.v gds/
	cp -f done/results/magic/wrapper_sha1.gds gds/
	cp -f done/results/magic/wrapper_sha1.gds.png gds/
	cp -f done/results/magic/.magicrc gds/
	cp -f done/results/magic/wrapper_sha1.lef gds/

.PHONY: gds
gds: done/results/lvs/wrapper_sha1.lvs.powered.v
	cp -f done/results/lvs/wrapper_sha1.lvs.powered.v gds/
	awk '1;/wbs_sel_i);/{ print "`ifdef COCOTB_SIM"; print "initial begin"; print "$$dumpfile (\"wrapper.vcd\");"; print "$$dumpvars (0, wrapper_sha1);"; print "#1;"; print "end"; print "`endif"}' gds/wrapper_sha1.lvs.powered.v > gds/v
	cat gds/header gds/v > gds/wrapper_sha1.lvs.v
	$(MAKE) test_gds
	$(MAKE) test_lvs_wrapper

done/results/lvs/wrapper_sha1.lvs.powered.v:
	$(MAKE) test_sha1
	$(MAKE) test_wb_logic
	$(MAKE) test_wrapper
	$(MAKE) prove_sha1
	$(MAKE) run_gds

covered:
	$(MAKE) test_wrapper
	covered score -t wrapper_sha1 -I src/ -v src/wrapper_sha1.v -v src/sha1_wb.v -vcd wrapper.vcd -D MPRJ_IO_PADS=38 -i wrapper_sha1 -o final.cdd
	covered report -d v final.cdd

test_lvs_wrapper:
	rm -rf sim_build/
	mkdir sim_build/
	iverilog -o sim_build/sim.vvp -DMPRJ_IO_PADS=38 -I $(PDK_ROOT)/sky130A/ -s dump -g2012 gds/wrapper_sha1.lvs.v test/dump_wrapper.v
	PYTHONOPTIMIZE=${NOASSERT} MODULE=test.test_wrapper,test.test_wb_logic vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus sim_build/sim.vvp
	! grep failure results.xml

visualize: test_lvs_wrapper
	rm -Rf build
	mkdir -p build
	cp $(CELLS) build/tmp_$(PDK)_cells_fixed.v
	sed -i 's/wire 1/wire __1/g' build/tmp_$(PDK)_cells_fixed.v
	python3 $(CHIP_VIS_DIR)/chip-vis.py \
                    --cell_models build/tmp_$(PDK)_cells_fixed.v \
                    --gl_netlist $(GL) \
                    --vcd $(VCD) \
                    --gds $(GDS) \
                    --prefix "dump" \
		    --strip ".wrapper_sha1." \
                    --status_var "dump.status" \
		    --start_status "Active ON" \
                    --rst "dump.reset" \
                    --clk "dump.wb_clk_i" \
                    --outfile "vis.gif" \
                    --mode 3 \
                    --scale 3 \
                    --fps 10 \
                    --downscale 1 \
                    --blur 1 \
                    --exp_grow 1.2 \
                    --exp_decay 0.8 \
                    --lin_grow 0.15 \
                    --lin_decay 0.15 \
                    --build_dir ./
	for file in `ls *.gif`; do gifsicle -O3 --colors 256 --batch $$file & done; wait
	mv *.gif pics/

generated.yaml:
	cat $(CURDIR)/projects.yaml | sed "s|#HOME|$(CURDIR)/../|g" | sed "s|#GCC_PATH|$(GCC_PATH)|" | sed s"|#GCC_PREFIX|$(GCC_PREFIX)|" > $(CURDIR)/generated.yaml

multi_project: gds
	$(MAKE) clean
	$(MAKE) generated.yaml
	cd $(MULTI_PROJECT_DIR); \
		./multi_tool.py --config $(CURDIR)/generated.yaml --test-all --force-delete

caravel:
	cp -f gds/wrapper_sha1.lvs.powered.v $(TARGET_PATH)/verilog/gl/wrapper_sha1.v
	cp -f gds/wrapper_sha1.gds $(TARGET_PATH)/gds
	cp -f gds/wrapper_sha1.lef $(TARGET_PATH)/lef
	cp -f caravel_test/* $(TARGET_PATH)/verilog/dv/sha1_test/
	echo -n "GDS/LEF/GL from " > $(TARGET_PATH)/d
	git describe --always >> $(TARGET_PATH)/d
	sha1sum gds/wrapper_sha1.* >> $(TARGET_PATH)/d
	$(MAKE) -C $(TARGET_PATH) user_project_wrapper
	! grep "ERROR" $(TARGET_PATH)/openlane/user_project_wrapper/runs/user_project_wrapper/logs/flow_summary.log
	docker run -it \
		-v $(PRECHECK):/usr/local/bin \
		-v $(TARGET_PATH):$(TARGET_PATH) \
		-v $(PDK_ROOT):$(PDK_ROOT) \
		-v $(CARAVEL_ROOT):$(CARAVEL_ROOT) \
		-e TARGET_PATH=$(TARGET_PATH) \
		-e PDK_ROOT=$(PDK_ROOT) \
		-e CARAVEL_ROOT=$(CARAVEL_ROOT) \
		-u $(shell id -u $$USER):$(shell id -g $$USER) \
		efabless/open_mpw_precheck:latest \
		/bin/bash -c "./run_precheck.sh"

test_sha1:
	rm -rf sim_build/
	mkdir sim_build/
	iverilog -o sim_build/sim.vvp -DMPRJ_IO_PADS=38 -s sha1_wb -s dump -g2012 $(SOURCES) test/dump_sha1.v
	PYTHONOPTIMIZE=${NOASSERT} MODULE=test.test_sha1 vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus sim_build/sim.vvp
	! grep failure results.xml


prove_sha1:
	sby -f properties.sby

test_wrapper:
	rm -rf sim_build/
	mkdir sim_build/
	iverilog -o sim_build/sim.vvp -DMPRJ_IO_PADS=38  -s dump -g2012 $(SOURCES) test/dump_wrapper.v
	PYTHONOPTIMIZE=${NOASSERT} MODULE=test.test_wrapper,test.test_wb_logic vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus sim_build/sim.vvp
	! grep failure results.xml


test_wb_logic:
	rm -rf sim_build/
	mkdir sim_build/
	iverilog -o sim_build/sim.vvp -DMPRJ_IO_PADS=38  -s sha1_wb -s dump -g2012 $(SOURCES) test/dump_wb_logic.v
	PYTHONOPTIMIZE=${NOASSERT} MODULE=test.test_wb_logic vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus sim_build/sim.vvp
	! grep failure results.xml


show_%: %.vcd %.gtkw
	gtkwave $^

lint:
	verilator --lint-only ${SOURCES} --top-module wrapper_sha1
	verible-verilog-lint $(SOURCES) --rules_config verible.rules

.PHONY: clean
clean:
	rm -rf *vcd sim_build fpga/*log fpga/*bin test/__pycache__ done caravel_test/sim_build properties *.xml generated.yaml *.cdd

# FPGA recipes

show_synth_%: src/%.v
	yosys -p "read_verilog $<; proc; opt; show -colors 2 -width -signed"

%.json: $(SOURCES)
	yosys -l fpga/yosys.log -DFPGA=1 -DWIDTH=8 -p 'synth_ice40 -top fpga -json $(PROJECT).json' $(SOURCES)

%.asc: %.json $(ICEBREAKER_PIN_DEF)
	nextpnr-ice40 -l fpga/nextpnr.log --seed $(SEED) --freq 20 --package $(ICEBREAKER_PACKAGE) --$(ICEBREAKER_DEVICE) --asc $@ --pcf $(ICEBREAKER_PIN_DEF) --json $<

%.bin: %.asc
	icepack $< $@

prog: $(PROJECT).bin
	iceprog $<
