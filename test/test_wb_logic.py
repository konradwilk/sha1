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

async def test_ops(dut, wbs, wrapper, gl):

    if gl == 0:
        if wrapper:
            name = dut.sha1_wishbone.sha1_on
        else:
            name = dut.sha1_on

        name <= 0;
        await ClockCycles(dut.wb_clk_i, 5)
        assert name == 0

    cmd = CTRL_SHA1_OPS
    exp = 0x0;
    val = await read_val(dut, wbs, cmd, exp);
    assert (val == exp);

    exp = 1; # Turn ON!
    val = await write_val(dut, wbs, CTRL_SHA1_OPS, exp);
    assert(val == exp);

    exp = 1 << 1 | 0; # Reset and turn OFF
    val = await write_val(dut, wbs, CTRL_SHA1_OPS, exp);
    # Ignore the counter.
    assert((val & 0xf) == exp);

    if gl == 0:
        assert name == 0

    cmd = CTRL_SHA1_OPS
    exp = 0x0;
    val = await read_val(dut, wbs, cmd, exp);
    assert (val == exp);

    if gl == 0:
        assert name == 0

async def test_msg(dut, wbs, wrapper, gl):

    if gl == 0:
        if wrapper:
            name = dut.sha1_wishbone.message;
            idx = dut.sha1_wishbone.sha1_msg_idx;
        else:
            name = dut.message;
            idx = dut.sha1_msg_idx;

    # Noting is running, right?
    cmd = CTRL_SHA1_OPS
    exp = 0x0;
    val = await read_val(dut, wbs, cmd, exp);
    assert (val == exp);

    if gl == 0:
        name <= 0;
        await ClockCycles(dut.wb_clk_i, 5)
        assert name == 0

    cmd = CTRL_MSG_IN;
    exp = 0xfffffea;
    val = await read_val(dut, wbs, cmd, exp);
    assert (val == exp);

    if gl == 0:
        assert (idx == 0);

    # Sixteen writes only
    for i in range(16):
        cmd = CTRL_MSG_IN;
        # We write in the loop values.
        exp = i;

        if gl == 0:
            value = int(BinaryValue(str(idx.value)));
            #dut._log.info("write on loop %x idx=%x" % (i, value));
            assert (value == i);

        val = await write_val(dut, wbs, cmd, exp);
        assert (val == 1);

        # The internal loop value will increment by 1 after the write,
        # unless it is the 15th (0xf) write.

        if gl == 0:
            if i == 15:
                exp = 0;
            else:
                exp = i+1;
            value = int(BinaryValue(str(idx.value)));
            assert (value == exp);

        cmd = CTRL_SHA1_OPS
        if i == 15:
          exp = 1;
        else:
          exp = 0x0;

        # 0xf is to ignore the loop counter.
        val = await read_val(dut, wbs, cmd, exp);
        assert (val & 0xf == exp);

        val = await read_val(dut, wbs, cmd, exp);
        assert (val & 0xf == exp);

        val = await read_val(dut, wbs, cmd, exp);
        assert (val & 0xf == exp);

    # Any writes after the sha1_on is set will return -EBUSY
    cmd = CTRL_MSG_IN;
    exp = 0;
    val = await write_val(dut, wbs, cmd, exp);

    assert (val == 0xfffffea);

    # Stop the engine.
    cmd = CTRL_SHA1_OPS
    exp = 1 << 1 | 0; # Reset and turn OFF
    val = await write_val(dut, wbs, CTRL_SHA1_OPS, exp);
    # Ignore the loop counter.
    assert(val & 0xf == exp);

    # Double check

    cmd = CTRL_SHA1_OPS
    exp = 0;
    val = await read_val(dut, wbs, cmd, exp);
    assert (val == exp);

    if gl == 1:
        return

    #value = int(BinaryValue(str(name.value)));
    #dut._log.info("msg=%s" % (value));

    # Check that we wrote the value correctly in (basically loop values);
    for i in range(16):
       # dut._log.info("%d -> %d" % (512-(i*32), 512-((i+1)*32)))
        value = str(name.value)[512-((i+1)*32):512-(i*32)];
        val = int(BinaryValue(value));
        dut._log.info("msg[%x] = val=%x" % (i, val));

        assert (val == i);

async def test_digest(dut, wbs, wrapper, gl):

    # We can't do this because we can't reach in the module and
    # set the sha1_done on.
    if gl:
        return

    if wrapper:
        name = dut.sha1_wishbone.digest;
        idx = dut.sha1_wishbone.sha1_digest_idx;
        done = dut.sha1_wishbone.sha1_done;
    else:
        name = dut.digest;
        idx = dut.sha1_digest_idx;
        done = dut.sha1_done;

    # Nothing is running, right?
    cmd = CTRL_SHA1_OPS
    exp = 0x0;
    val = await read_val(dut, wbs, cmd, exp);
    assert (val == exp);

    # Which means sha1_done is also off, so we get EBUSY.
    cmd = CTRL_SHA1_DIGEST;
    exp = 0xfffffea;
    val = await read_val(dut, wbs, cmd, exp);
    value = int(BinaryValue(str(idx.value)));

    val = 0;
    for i in range(5):
        val = val | ((i+1) << (i*32))
        dut._log.info("digest[%x] = val=0x%x" % (i, val));

    name <= val;
    await ClockCycles(dut.wb_clk_i, 5)
    assert name == val

    value = int(BinaryValue(str(name.value)));
    dut._log.info("digest=0x%x" % (value));
    # Also set sha1_done.
    done <= 1;

    # Five reads only
    for i in range(5):
        value = int(BinaryValue(str(idx.value)));
        dut._log.info("read on loop %x idx=%x" % (i, value));
        assert (value == i);

        cmd = CTRL_SHA1_DIGEST;

        # We read in the loop values + 1.
        exp = i + 1;

        val = await read_val(dut, wbs, cmd, exp);
        assert (val == exp);


    # Any read after the sha1_done is set will return -EBUSY
    cmd = CTRL_SHA1_DIGEST;
    exp = 1;
    val = await read_val(dut, wbs, cmd, exp);

    value = int(BinaryValue(str(idx.value)));
    dut._log.info("outside val=%s idx=%x" % (val, value));
    assert (val == exp);

    # Stop the engine.
    done <= 0;

    cmd = CTRL_SHA1_OPS
    exp = 1 << 1 | 0; # Reset and OFF
    val = await write_val(dut, wbs, CTRL_SHA1_OPS, exp);
    assert(val == exp);

async def test_engine(dut, wbs, wrapper, gl):

    # Nothing is running, right?
    cmd = CTRL_SHA1_OPS
    exp = 0x0;
    val = await read_val(dut, wbs, cmd, exp);
    assert (val == exp);

    for i in range(16):
        cmd = CTRL_MSG_IN;
        # We write in the loop values.
        exp = i;

        val = await write_val(dut, wbs, cmd, exp);
        assert (val == 1);

    cmd = CTRL_SHA1_OPS
    exp = 0x1; # It should be on
    val = await read_val(dut, wbs, cmd, exp);
    assert (val & 0xf == exp);

    # We wait until sha1_done
    for i in range(200):
        await ClockCycles(dut.wb_clk_i, 5)

        exp = 1 << 3;
        val = await read_val(dut, wbs, CTRL_SHA1_OPS, exp);
        # buffer_o <= {22'b0, sha1_loop_idx, sha1_done, sha1_panic, sha1_reset, sha1_on};
        sha1_loop_idx = (val & 0xff0) >> 4;
        state = (val & 0xf);
        dut._log.info("loop[%d] = loop_idx = %d, state = 0x%x" % (i, sha1_loop_idx, state));

        if (val & exp):
            break;

    exp = 1 << 3;
    val = await read_val(dut, wbs, CTRL_SHA1_OPS, exp);
    assert (val & exp);

    # Five reads only
    for i in range(5):
        cmd = CTRL_SHA1_DIGEST;
        exp = 0;
        val = await read_val(dut, wbs, CTRL_SHA1_DIGEST, exp);
        dut._log.info("digest[%x] = val=0x%x" % (i, val));

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

    # Activate is la_data_in[2].
    dut.la_data_in <= 1 << 2 | 0;
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

    await test_ops(dut, wbs, wrapper, gl);

    await test_msg(dut, wbs, wrapper, gl);

    await test_digest(dut, wbs, wrapper, gl);

    await test_engine(dut, wbs, wrapper, gl);
