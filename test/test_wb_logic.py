import cocotb
import inspect
from cocotb.clock import Clock
from cocotb.binary import BinaryValue
from cocotb.triggers import ClockCycles
from cocotbext.wishbone.driver import WishboneMaster
from cocotbext.wishbone.driver import WBOp

async def read_val(dut, wbs, cmd, exp):
    wbRes = await wbs.send_cycle([WBOp(cmd)]);
    dut._log.info("%s = Read %s expected %s" % (hex(cmd), hex(wbRes[0].datrd.integer), hex(exp)))
    return wbRes[0].datrd.integer

async def write_val(dut, wbs, cmd, val):
    dut._log.info("%s <= Writing %s" % (hex(cmd), hex(val)));
    wbRes = await wbs.send_cycle([WBOp(cmd, dat=val)]);
    val = wbRes[0].datrd.integer
    dut._log.info("%s <= (ret=%s)" % (hex(cmd),  hex(val)));
    return val

CTRL_GET_NR         = 0x30000024
CTRL_GET_ID         = CTRL_GET_NR + 0x4
CTRL_SHA1_OPS       = CTRL_GET_NR + 0x8
CTRL_MSG_IN         = CTRL_GET_NR + 0xC
CTRL_SHA1_DIGEST    = CTRL_GET_NR + 0x10

async def test_id(dut, wbs):
    for i in range(10):
        cmd = CTRL_GET_ID;
        exp = 0x53484131;
        val = await read_val(dut, wbs, cmd, exp);
        assert (val == exp);
        cmd = CTRL_GET_NR;
        # First version has only 4 commands
        if (exp == 0x53484131):
            exp = 4;

        val = await read_val(dut, wbs, cmd, exp);
        assert (val == exp);

async def test_irq(dut, wbs, wrapper):

    if wrapper:
        name = dut.irq
    else:
        name = dut.irq_out;

    name <= 0;
    await ClockCycles(dut.wb_clk_i, 5)
    assert name == 0

    val = await write_val(dut, wbs, CTRL_SHA1_OPS, 1);
    assert(val == 2);

    await ClockCycles(dut.wb_clk_i, 5)
    assert (name == 1)

    val = await write_val(dut, wbs, CTRL_SET_IRQ, 0);
    assert(val == 1);

    await ClockCycles(dut.wb_clk_i, 5)
    dut._log.info("IRQ=%s" % (name.value));

    assert(name.value == 0);


async def activate_wrapper(dut):

    await ClockCycles(dut.wb_clk_i, 5)

    dut.active <= 0
    dut.wb_rst_i <= 1
    await ClockCycles(dut.wb_clk_i, 5)
    dut.wb_rst_i <= 0
    dut.la_data_in <= 0

    dut._log.info("io_out=%s" % (dut.io_out.value));
    # We get these annoying 'ZZ' in there, so we do this dance to get rid of it.
    value = BinaryValue(str(dut.io_out.value)[:-8].replace('z','').replace('x',''));

    assert(str(value) == "");

    await ClockCycles(dut.wb_clk_i, 100)

    dut.active <= 1
    # Reset pin is hooked up to la_data_in[0].
    dut.la_data_in <= 1 << 0
    await ClockCycles(dut.wb_clk_i,2)

    dut.la_data_in <= 0 << 0
    await ClockCycles(dut.wb_clk_i,1)

@cocotb.test()
async def test_wb_logic(dut):
    clock = Clock(dut.wb_clk_i, 10, units="ns")
    cocotb.fork(clock.start())
    wbs = WishboneMaster(dut, "wbs", dut.wb_clk_i,
                          width=32,   # size of data bus
                          timeout=10, # in clock cycle number
                          signals_dict={"cyc":  "cyc_i",
                                      "stb":  "stb_i",
                                      "we":   "we_i",
                                      "adr":  "adr_i",
                                      "datwr":"dat_i",
                                      "datrd":"dat_o",
                                      "ack":  "ack_o",
                                      "sel": "sel_i"})
    gl = False
    try:
        dut.vssd1 <= 0
        dut.vccd1 <= 1
        gl = True
    except:
        pass
    # This exists in WishBone code only.
    try:
        dut.reset <= 1
        await ClockCycles(dut.wb_clk_i, 5)
        dut.reset <= 0
    except:
        pass

    wrapper = False
    # While this is for for wrapper
    try:
        await activate_wrapper(dut);
        wrapper = True
    except:
        pass

    await ClockCycles(dut.wb_clk_i, 100)

    await test_id(dut, wbs);

