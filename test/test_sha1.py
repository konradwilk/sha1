import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotb.binary import BinaryValue

import ctypes

DEFAULT     = 0xf00df00d;

STATE_INIT  = 0;
STATE_START = 1;
LOOP_ONE    = 2;
LOOP_TWO    = 3;
LOOP_THREE  = 4;
LOOP_FOUR   = 5;
STATE_DONE  = 6;
STATE_FINAL = 7;
STATE_PANIC = 8;

INITIAL_H0  = 0x67452301;
INITIAL_H1  = 0xEFCDAB89;
INITIAL_H2  = 0x98BADCFE;
INITIAL_H3  = 0x10325476;
INITIAL_H4  = 0xC3D2E1F0;

async def reset(dut):

    dut.sha1_on <= 0;
    dut.reset <= 1
    await ClockCycles(dut.wb_clk_i, 5)
    dut.reset <= 0

async def payload(dut):

    assert (dut.state == STATE_INIT);

    await ClockCycles(dut.wb_clk_i, 5)

    for i in range(len(dut.message)):
       dut.message[i] <= 0;

    dut.message[0] <= 0x61626380;
    dut.message[15] <= 0x18; # abc

    assert (dut.state == STATE_INIT);

    await ClockCycles(dut.wb_clk_i, 1)

    dut.sha1_on <= 1;
    await ClockCycles(dut.wb_clk_i, 1)
    assert (dut.state == STATE_INIT);

    await ClockCycles(dut.wb_clk_i, 1)
    assert (dut.state == STATE_START);


async def loop_one(dut):

    assert (dut.state == STATE_START);
    await ClockCycles(dut.wb_clk_i, 1)

    for i in range(len(dut.message)):
        dut._log.info("%d = [%s]" % (i, hex(BinaryValue(str(dut.message[i].value)))));
        if i == 0:
           assert(dut.message[i].value == 0x61626380);
        if i == 15:
           assert(dut.message[i].value == 0x18);

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

    # Now lets compute the first function.
    a = INITIAL_H0;
    b = INITIAL_H1;
    c = INITIAL_H2;
    d = INITIAL_H3;
    e = INITIAL_H4;
    k = 0x5A827999;

    #assert (dut.w == int(msg));

    for i in range(19):

        assert (dut.index == i);

        # Compute cycle:
        f = (b & c) | ((~b) & d);
        w = int(dut.w);
        a_left_5 = (a << 5| a >> 27) & 0xFFFFFFFF;
        temp = ctypes.c_uint(a_left_5 + f + e + k + w).value;

        assert (dut.compute == 1);
        assert (dut.copy_values == 0);

        # Crank it and ..
        await ClockCycles(dut.wb_clk_i, 1)

        # Note that we probe for dut.temp here, and the inc_counter had fired
        # of in previous clock cycle, so we are at:
        assert (dut.index == i+1);

        # And the dut.temp contais the value from the previous index value.

        dut._log.info("i=%2d w=%8x temp=%8x (temp=%8x)" % (i, w, int(dut.temp), temp));

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
        await ClockCycles(dut.wb_clk_i, 1)

        assert (dut.compute == 1);
        assert (dut.copy_values == 0);
        assert (dut.inc_counter == 1);

        # Also we did some transformations on a, b, c, d..
        assert (dut.e == d);
        assert (dut.b == a);
        assert (dut.a == temp);

        e = d;
        d = c;
        c = ctypes.c_uint((b << 30 | b >> 2) & 0xFFFFFFFF).value;
        b = a;
        a = temp;


async def loop(dut, loop_state, idx, k, loop_cnt):

    assert (int(dut.state) + 1 == loop_state);
    # Start at the previous loop.
    assert (dut.index == idx);
    assert (dut.k != k);

    for i in range(loop_cnt):

        w = int(dut.w);
        idx = int(dut.index);

        await ClockCycles(dut.wb_clk_i, 1)
        # It is a two clock cycle operation. In the first we copy_values:
        assert (dut.copy_values == 1);
        assert (dut.compute == 0);

        assert (int(dut.state)  == loop_state);

        await ClockCycles(dut.wb_clk_i, 1)
        # Now we actually compute the value
        assert (dut.copy_values == 0);
        assert (dut.compute == 1);

        # And the index had moved from the start of the loop
        assert (dut.index == idx + 1);

        temp = int(dut.temp);
        dut._log.info("i=%2d w=%8x temp=%8x" % (idx, w, temp));

    dut._log.info("%d=%d finished with idx=%d" % (int(dut.state), loop_state, int(dut.index)));

async def loop_done(dut, idx, k):

    # Crank it over (let it do its compute and increase index)
    await ClockCycles(dut.wb_clk_i, 1)

    assert (dut.state == STATE_DONE);
    assert (dut.k == k);
    assert (dut.index == idx);

    # Now let is copy the values over
    assert (dut.copy_values == 1);
    await ClockCycles(dut.wb_clk_i, 1)

    assert (dut.copy_values == 0);
    dut._log.info("i=%2d temp=%8x" % (dut.index, int(dut.temp)));

    assert(int(dut.temp) == 0x42541b35);
    dut._log.info("A=%8x" % (int(dut.a)));
    assert(int(dut.a) == 0x42541b35);
    dut._log.info("B=%8x" % (int(dut.b)));
    assert(int(dut.b) == 0x5738d5e1);
    dut._log.info("C=%8x" % (int(dut.c)));
    assert(int(dut.c) == 0x21834873);
    dut._log.info("D=%8x" % (int(dut.d)));
    assert(int(dut.d) == 0x681e6df6);
    dut._log.info("E=%8x" % (int(dut.d)));
    assert(int(dut.e) == 0xd8fdf6ad);


    # The finish wire is not set.
    assert (dut.finish == 0);

    # Lets turn it over so the addition to Hx can be
    # registered
    await ClockCycles(dut.wb_clk_i, 1)

    assert (dut.index == 0);
    assert (dut.state == STATE_FINAL);

    assert (dut.h0 == 0xa9993e36);
    assert (dut.h1 == 0x4706816a);
    assert (dut.h2 == 0xba3e2571);
    assert (dut.h3 == 0x7850c26c);
    assert (dut.h4 == 0x9cd0d89d);
    # But now it is !
    assert (dut.finish == 1);

    dut._log.info("digest=%x " % (int(dut.digest.value)));
    assert (int(dut.digest) == 0xa9993e364706816aba3e25717850c26c9cd0d89d);

    # Just spin for fun.
    for i in range(20):
       await ClockCycles(dut.wb_clk_i, 1)
       assert (dut.finish == 1);

    assert (dut.index == 0);


async def loop_final(dut):

    assert (dut.state == STATE_FINAL);
    assert (dut.sha1_on == 1);
    assert (dut.finish == 1);

    await ClockCycles(dut.wb_clk_i, 1)

    # Lets toggle the 'on' down, the state should go back to INIT
    # It takes two cycles - one to register sha1_on going down, the
    # other to register the state moving to STATE_INIT.

    dut.sha1_on <= 0;
    await ClockCycles(dut.wb_clk_i, 2)

    dut._log.info("state=%d " % (int(dut.state.value)));

    assert (dut.state == STATE_INIT);
    assert (dut.sha1_on == 0);
    assert (dut.finish == 0);

@cocotb.test()
async def test_sha1(dut):

    clock = Clock(dut.wb_clk_i, 10, units="us")
    cocotb.fork(clock.start())

    await reset(dut)

    for i in range(3):
        await payload(dut)

        await loop_one(dut)

        await loop(dut, LOOP_TWO, 19, 0x6ED9EBA1, 20);

        await loop(dut, LOOP_THREE, 39, 0x8F1BBCDC, 20);

        await loop(dut, LOOP_FOUR, 59, 0xCA62C1D6, 20);

        await loop_done(dut, 80, 0xf00df00d);

        await loop_final(dut);
