# SPDX-FileCopyrightText: 2021 Konrad Rzeszutek Wilk
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
# SPDX-License-Identifier: Apache-2.0
import cocotb
from cocotb.clock import Clock
from cocotb.binary import BinaryValue
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_wrapper(dut):
    clock = Clock(dut.wb_clk_i, 10, units="ns")
    cocotb.fork(clock.start())

    clocks_per_phase = 5
    dut.la_data_in <= 0 << 0;
    try:
        dut.vssd1 <= 0
        dut.vccd1 <= 1
        dut.RSTB <= 0
        dut.power1 <= 0;
        dut.power2 <= 0;
        dut.power3 <= 0;
        dut.power4 <= 0;
    except:
        pass

    dut._log.info("Cycling power");
    await ClockCycles(dut.wb_clk_i, 8)
    dut.power1 <= 1;
    await ClockCycles(dut.wb_clk_i, 8)
    dut.power2 <= 1;
    await ClockCycles(dut.wb_clk_i, 8)
    dut.power3 <= 1;
    await ClockCycles(dut.wb_clk_i, 8)
    dut.power4 <= 1;

    dut.status <= 0
    dut.wbs_dat_i <= 0
    dut.wbs_dat_o <= 0
    dut.wbs_sel_i <= 0
    dut.wbs_adr_i <= 0
    dut.wbs_we_i <= 0;
    dut.wbs_ack_o <= 0;
    dut.wb_rst_i <= 0
    dut.wbs_stb_i <= 0
    dut.wbs_cyc_i <= 0
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

    dut._log.info("io_out=%s" % (dut.io_out.value));
    value = BinaryValue(str(dut.io_out.value)[:-8].replace('z','').replace('x',''));
    assert (int(value) == 0);

