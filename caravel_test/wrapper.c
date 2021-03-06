/*
 * SPDX-FileCopyrightText: 2020 Efabless Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * SPDX-License-Identifier: Apache-2.0
 */

#include "verilog/dv/caravel/defs.h"
#include "verilog/dv/caravel/stub.c"

#define BASE_ADDRESS 		0x30000024
#define CTRL_GET_NR		(BASE_ADDRESS + 0x00)
#define CTRL_GET_ID		(BASE_ADDRESS + 0x04)
#define CTRL_SHA1_OPS		(BASE_ADDRESS + 0x08)
#define CTRL_MSG_IN		(BASE_ADDRESS + 0x0C)
#define CTRL_SHA1_DIGEST	(BASE_ADDRESS + 0x10)
#define CTRL_PANIC		(BASE_ADDRESS + 0x14)

#define CTRL_ID			0x53484131
#define CTRL_NR			4

static uint32_t read(unsigned long addr)
{
	return *(volatile uint32_t *)addr;
}

static void write(unsigned long addr, uint32_t val)
{
	*(volatile uint32_t *)addr = val;
}


void configure_gpio(void)
{
        reg_mprj_io_37 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_36 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_35 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_34 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_33 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_32 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_31 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_30 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_29 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_28 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_27 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_26 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_25 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_24 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_23 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_22 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_21 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_20 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_19 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_18 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_17 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_16 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_15 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_14 = GPIO_MODE_USER_STD_OUTPUT;

        reg_mprj_io_13 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_12 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_11 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_10 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_9 = GPIO_MODE_USER_STD_OUTPUT;
        reg_mprj_io_8 = GPIO_MODE_USER_STD_OUTPUT;

	/* Enable user IRQs */
	reg_mprj_irq = 1;
}

void activate(void)
{
	/* [31:0] is	reg_la0_oenb, 0x2500,0010
	 * [63:32] is	reg_la1_oenb, 0x2500,0014
	 * [95:64] is	reg_la2_oenb  0x2500,0018
	 * [127:96] is	reg_la3_oenb  0x2500,001C
	 *
	 * All data go on la_data_in[127:0] , which starts
	 * at 0x2500,0000
	 */
	reg_la1_iena = 0 << 4; /* 0x25000024: Input enable off */
	reg_la1_oenb = 0 << 4; /* 0x25000014: 32th, corresponds to active */
	/* .active() HIGH */
	reg_la1_data = 1 << 4; /* 0x25000004 */
}

void reset(void)
{
	/* .reset(la_data_in[0]) */
	reg_la0_iena = 0;
	reg_la0_oenb = 0; /* 0x2500,0010 */

	reg_la0_data = 1; /* RST on 0x2500,0000*/
	reg_la0_data = 0; /* RST off */
}

void panic(uint32_t line)
{
	/* TODO: Strobe LEDs or UART. 6/7*/
	do {
		write(CTRL_PANIC, line);
	} while (1);

}
#define BUG_ON(x) { if ((x)) panic(__LINE__); }

#define MAGIC_VAL 0xdeadbeef
#define MAGIC_END 0x0badf00d

volatile bool flag;

// gets jumped to from the interrupt handler defined in start.S
uint32_t *irq()
{
	flag = 0;

	write(CTRL_SHA1_OPS, 0); /* Ack the IRQ */

	write(CTRL_PANIC, MAGIC_END);
}

void wishbone_test(void)
{
	uint32_t val, i;

	val = read(CTRL_GET_ID);
	BUG_ON(val != CTRL_ID);

	val = read(CTRL_GET_NR);
	BUG_ON(val != CTRL_NR);

        /* The sha1_done should _NOT_ be set */
	val = read(CTRL_SHA1_OPS);
        BUG_ON(val & 0x1 == 0x1)

	write(CTRL_MSG_IN, 0x61626380); /* [0]= */
        for (i = 1; i < 15; i++)
		write(CTRL_MSG_IN, 0x0);

        write(CTRL_MSG_IN, 0x18); /* [15]= */

        /* The sha1_done should be set */
	val = read(CTRL_SHA1_OPS);
        BUG_ON(val & 0x1 != 0x1)

        do {
	   val = read(CTRL_SHA1_OPS);
           /* [3] will be set when it is done. */
           if (val & 1 << 3)
              break;
        } while (val & 1); /* Spin as long as sha1_on is set */


        val = read(CTRL_SHA1_DIGEST);
        BUG_ON(val != 0xa9993e36);

        val = read(CTRL_SHA1_DIGEST);
        BUG_ON(val != 0x4706816a);

        val = read(CTRL_SHA1_DIGEST);
        BUG_ON(val != 0xba3e2571);

        val = read(CTRL_SHA1_DIGEST);
        BUG_ON(val != 0x7850c26c);

        val = read(CTRL_SHA1_DIGEST);
        BUG_ON(val != 0x9cd0d89d);

	do {
		// Spin until IRQ come in (it may already..)
	} while (flag);

	write(CTRL_PANIC, MAGIC_END);
}

void main()
{
	flag = 1;

	// All GPIO pins are configured to be output
	configure_gpio();

        /* Apply configuration */
        reg_mprj_xfer = 1;
        while (reg_mprj_xfer == 1);

	activate();

	reset();

	wishbone_test();
	/* There it goes .. */

}

