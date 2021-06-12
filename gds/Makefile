# cocotb setup
export COCOTB_REDUCED_LOG_FMT=1
MODULE = test_wrapper
TOPLEVEL = wrapper_sha1
VERILOG_SOURCES = wrapper_sha1.lvs.v

COMPILE_ARGS=-I $(PDK_ROOT)/sky130A/ -DMPRJ_IO_PADS=38

include $(shell cocotb-config --makefiles)/Makefile.sim

show:
	gtkwave wrapper.vcd wrapper.gtkw

.PHONY: clean
clean::
	rm -rf *vcd __pycache__ sim-build results.xml
