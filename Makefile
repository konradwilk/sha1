
PROJECT = fpga/sha1
SOURCES= src/sha1.v src/wrapper_sha1.v src/sha1_wb.v
ICEBREAKER_DEVICE = up5k
ICEBREAKER_PIN_DEF = fpga/icebreaker.pcf
ICEBREAKER_PACKAGE = sg48
SEED = 1
MULTI_PROJECT_DIR ?= $(PWD)/../multi_project_tools
GCC_PATH ?= /opt/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-linux-centos6/bin
GCC_PREFIX ?= riscv64-unknown-elf

# COCOTB variables
export COCOTB_REDUCED_LOG_FMT=1

all: test_sha1 test_wb_logic test_wrapper prove_sha1

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
	cp -f done/results/lvs/wrapper_sha1.lvs.powered.v gds/
	cp -f done/results/magic/wrapper_sha1.gds gds/
	cp -f done/results/magic/wrapper_sha1.gds.png gds/
	cp -f done/results/magic/.magicrc gds/
	cp -f done/results/magic/wrapper_sha1.lef gds/

.PHONY: gds
gds: done/results/lvs/wrapper_sha1.lvs.powered.v
	awk '1;/wbs_sel_i);/{ print "`ifdef COCOTB_SIM"; print "initial begin"; print "$$dumpfile (\"wrapper.vcd\");"; print "$$dumpvars (0, wrapper_sha1);"; print "#1;"; print "end"; print "`endif"}' done/results/lvs/wrapper_sha1.lvs.powered.v > gds/v
	cat gds/header gds/v > gds/wrapper_sha1.lvs.powered.v
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
	covered score -t wrapper_sha1 -I src/ -v src/wrapper.v -v src/wb_logic.v -v src/sha1.v -vcd wrapper.vcd -D MPRJ_IO_PADS=38 -i wrapper_sha1 -o final.cdd
	covered report -d v final.cdd

test_lvs_wrapper:
	rm -rf sim_build/
	mkdir sim_build/
	iverilog -o sim_build/sim.vvp -DMPRJ_IO_PADS=38 -I $(PDK_ROOT)/sky130A/ -s wrapper_sha1 -s dump -g2012 gds/wrapper_sha1.lvs.powered.v  test/dump_wrapper.v
	PYTHONOPTIMIZE=${NOASSERT} MODULE=test.test_wrapper,test.test_wb_logic vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus sim_build/sim.vvp

generated.yaml:
	cat $(CURDIR)/projects.yaml | sed "s|#HOME|$(CURDIR)/../|g" | sed "s|#GCC_PATH|$(GCC_PATH)|" | sed s"|#GCC_PREFIX|$(GCC_PREFIX)|" > $(CURDIR)/generated.yaml

multi_project: gds
	$(MAKE) clean
	$(MAKE) generated.yaml
	cd $(MULTI_PROJECT_DIR); \
		./multi_tool.py --config $(CURDIR)/generated.yaml --test-all --force-delete

test_sha1:
	rm -rf sim_build/
	mkdir sim_build/
	iverilog -o sim_build/sim.vvp -s sha1 -s dump -g2012 src/sha1.v test/dump_sha1.v
	PYTHONOPTIMIZE=${NOASSERT} MODULE=test.test_sha1 vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus sim_build/sim.vvp

prove_sha1:
	sby -f properties.sby

test_wrapper:
	rm -rf sim_build/
	mkdir sim_build/
	iverilog -o sim_build/sim.vvp -DMPRJ_IO_PADS=38 -s wrapper_sha1 -s dump -g2012 $(SOURCES) test/dump_wrapper.v
	PYTHONOPTIMIZE=${NOASSERT} MODULE=test.test_wrapper,test.test_wb_logic vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus sim_build/sim.vvp

test_wb_logic:
	rm -rf sim_build/
	mkdir sim_build/
	iverilog -o sim_build/sim.vvp -DMPRJ_IO_PADS=38  -s sha1_wb -s dump -g2012 src/sha1_wb.v src/sha1.v test/dump_wb_logic.v
	PYTHONOPTIMIZE=${NOASSERT} MODULE=test.test_wb_logic vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus sim_build/sim.vvp

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
