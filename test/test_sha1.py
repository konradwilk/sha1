import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
import ctypes

SHA         = 0x534841;
STATE_INIT  = 0;
STATE_START = 1;
LOOP_ONE    = 2;
LOOP_TWO    = 3;
LOOP_THREE  = 4;
STATE_DONE  = 6;
STATE_FINAL = 7;
STATE_PANIC = 8;

INITIAL_H0  = 0x67452301;
INITIAL_H1  = 0xEFCDAB89;
INITIAL_H2  = 0x98BADCFE;
INITIAL_H3  = 0x10325476;
INITIAL_H4  = 0xC3D2E1F0;

async def reset(dut):

    dut.on <= 0;
    dut.reset <= 1
    await ClockCycles(dut.clk, 5)
    dut.reset <= 0

async def payload(dut, msg):

    assert (dut.state == STATE_INIT);

    await ClockCycles(dut.clk, 5)

    dut.message_in <= msg;

    assert (dut.state == STATE_INIT);

    await ClockCycles(dut.clk, 1)

    dut.on <= 1;
    await ClockCycles(dut.clk, 1)
    assert (dut.state == STATE_INIT);

    await ClockCycles(dut.clk, 1)
    assert (dut.state == STATE_START);

async def loop_one(dut, msg):

    assert (dut.state == STATE_START);
    await ClockCycles(dut.clk, 1)

    assert (dut.state == LOOP_ONE);

    assert (dut.h0 == INITIAL_H0);
    assert (dut.h1 == INITIAL_H1);
    assert (dut.h2 == INITIAL_H2);
    assert (dut.h3 == INITIAL_H3);
    assert (dut.h4 == INITIAL_H4);

    assert (dut.a == INITIAL_H0);
    assert (dut.b == INITIAL_H1);
    assert (dut.c == INITIAL_H2);
    assert (dut.d == INITIAL_H3);
    assert (dut.e == INITIAL_H4);

    assert (dut.compute == 1);
    assert (dut.copy_values == 0);
    assert (dut.index == 0);

    assert (dut.temp == 0xf00df00d);

    # Now lets compute the first function.
    a = INITIAL_H0;
    b = INITIAL_H1;
    c = INITIAL_H2;
    d = INITIAL_H3;
    e = INITIAL_H4;
    k = 0x5A827999;

    for i in range(10):

        assert (dut.index == i);

        # Compute cycle:
        f = (b & c) | ((-b) & d);
        temp = ctypes.c_uint(ctypes.c_uint(a << 5).value + f + e + k + int(dut.w)).value;

        assert (dut.compute == 1);
        assert (dut.copy_values == 0);

        # Crank it and ..
        await ClockCycles(dut.clk, 1)

        dut._log.info("i=%d dut.temp = %x temp=%x" % (i, int(dut.temp), temp));

        # Better have same values!
        assert (dut.temp == temp);

        # .. on the next cycle (for copy) we will overwrite a, b, c, d, ..

        assert (dut.compute == 0);
        assert (dut.copy_values == 1);

        # but before that in the compute cycle we copied a,b,c,d over.
        assert (dut.a_old == a);
        assert (dut.b_old == b);
        assert (dut.c_old == c);
        assert (dut.d_old == d);

        # Crank it and we have copied values over
        await ClockCycles(dut.clk, 1)

        assert (dut.compute == 1);
        assert (dut.copy_values == 0);
        assert (dut.inc_counter == 1);

        # Also we did some transformations on a, b, c, d..
        assert (dut.e == d);
        assert (dut.b == a);
        assert (dut.a == temp);

        e = d;
        d = c;
        c = ctypes.c_uint(b << 30).value;
        b = a;
        a = temp;

@cocotb.test()
async def test_sha1(dut):

    clock = Clock(dut.clk, 10, units="us")
    cocotb.fork(clock.start())

    await reset(dut)

    await payload(dut, int(SHA))

    await loop_one(dut, int(SHA))
