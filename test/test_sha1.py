import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

SHA         = 0x534841;
STATE_INIT  = 0;
STATE_START = 1;
LOOP_ONE    = 2;
LOOP_TWO    = 3;
LOOP_THREE  = 4;
STATE_DONE  = 6;
STATE_FINAL = 7;
STATE_PANIC = 8;

async def reset(dut):

    dut.reset <= 1
    await ClockCycles(dut.clk, 5)
    dut.reset <= 0

@cocotb.test()
async def test_sha1(dut):

    clock = Clock(dut.clk, 10, units="us")
    cocotb.fork(clock.start())

    dut.on <= 0;
    await reset(dut)

    assert (dut.state == STATE_INIT);

    await ClockCycles(dut.clk, 5)

    dut.message_in <= int(SHA);

    assert (dut.state == STATE_INIT);

    await ClockCycles(dut.clk, 5)

    assert (dut.state == STATE_INIT);
    dut.on <= 1;
