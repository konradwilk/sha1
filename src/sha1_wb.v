`default_nettype none
`timescale 1ns/1ns
`ifdef FORMAL
`define MPRJ_IO_PADS 38
`endif
`ifdef VERILATOR
`define MPRJ_IO_PADS 38
`endif

module sha1_wb #(
    parameter    [31:0] BASE_ADDRESS   = 32'h30000024,
    parameter  IDX_WIDTH = 6
    ) (
    input wire reset,

    output wire done,
    output wire irq,

    /* WishBone logic */

    input wire wb_clk_i,
    input wire wb_rst_i,
    input wire wbs_stb_i, /* strobe */
    input wire wbs_cyc_i,
    input wire wbs_we_i,
    input wire [3:0] wbs_sel_i,
    input wire [31:0] wbs_dat_i,
    input wire [31:0] wbs_adr_i,
    output wire wbs_ack_o,
    output wire [31:0] wbs_dat_o

);
    wire wb_active = wbs_stb_i & wbs_cyc_i;

    reg [31:0] buffer;
    reg [31:0] buffer_o;

    reg sha1_on;
    reg sha1_reset;
    wire sha1_wire_rst;
    reg sha1_panic;
    reg sha1_done;
    wire finish;
    reg [2:0] sha1_digest_idx;
    reg [IDX_WIDTH:0] index;
    reg [6:0] sha1_msg_idx;
    reg [159:0] digest;
    reg [511:0] message;
    reg transmit;

    /* CTRL_GET parameters. */
    localparam CTRL_GET_NR		= BASE_ADDRESS;
    localparam CTRL_NR 			= 4;

    localparam CTRL_GET_ID		= BASE_ADDRESS + 'h4;
    localparam CTRL_ID			= 32'h53484131; /* SHA1 */
    localparam DEFAULT			= 32'hf00df00d;
    /*
     * When writing: The [2:0] are operations.
     * When reading: [10:4] in what loop we are [0->79]. [1:0] are operations.
     */
    localparam CTRL_SHA1_OPS    = BASE_ADDRESS + 'h8;
    localparam ON			    = 4'b0001;
    localparam OFF			    = 4'b0000;
    localparam RESET			= 4'b0010;
    localparam PANIC			= 4'b0100; /* Can only be read. */
    localparam DONE			    = 4'b1000; /* Can only be read. */

    /* This requires 16 CTRL_MSG_IN and after that we start processing. */
    localparam CTRL_MSG_IN		= BASE_ADDRESS + 'hC;
    localparam ACK			    = 32'h0000001;
    localparam EINVAL			= 32'hfffffea; /* -14 */

    /* Five reads for the digest. */
    localparam CTRL_SHA1_DIGEST 		= BASE_ADDRESS + 'h10;
    localparam EBUSY            = 32'hfffffff0; /* -10 */

    always @(posedge wb_clk_i) begin
        if (reset) begin
            buffer_o <= DEFAULT;
            buffer <= DEFAULT;
            sha1_panic <= 1'b0;
            transmit <= 1'b0;
            sha1_msg_idx <= 0;
            sha1_digest_idx <= 0;
            sha1_done <= 0;
            sha1_reset <= 1'b1; /* Reset the SHA1 compute engine */
            sha1_on <= 0;
        end else begin
            if (transmit)
                transmit <= 1'b0;

            if (sha1_reset)
                sha1_reset <= 1'b0;

            if (finish)
                sha1_done <= 1'b1;
		    /* Read case */
            if (wb_active && !wbs_we_i) begin
                case (wbs_adr_i)
                    CTRL_GET_NR:
                    begin
                        buffer_o <= CTRL_NR;
                    end
                    CTRL_GET_ID:
                        buffer_o <= CTRL_ID;
                    CTRL_MSG_IN:
                        buffer_o <= EINVAL;
                    CTRL_SHA1_OPS:
                        buffer_o <= {21'b0, index, sha1_done, sha1_panic, sha1_reset, sha1_on};
                    CTRL_SHA1_DIGEST:
                    begin
                        if (sha1_done) begin
                            case (sha1_digest_idx)
                                'h0: buffer_o <= digest[31:0];
                                'h1: buffer_o <= digest[63:32];
                                'h2: buffer_o <= digest[95:64];
                                'h3: buffer_o <= digest[127:96];
                                'h4: buffer_o <= digest[159:128];
                                default: sha1_panic <= 1'b1;
                            endcase
                            if (!transmit) begin
                                if (sha1_digest_idx == 4)
                                    sha1_digest_idx <= 0;
                                else
                                    sha1_digest_idx <= sha1_digest_idx + 1'b1;
                            end
                        end else
                            buffer_o <= EBUSY;
                    end
                endcase
                if ((wbs_adr_i[31:0] >= BASE_ADDRESS) && (wbs_adr_i <= CTRL_SHA1_DIGEST))
                    transmit <= 1'b1;
            end
		    /* Write case */
            if (wb_active && wbs_we_i && &wbs_sel_i) begin
                case (wbs_adr_i)
                    CTRL_SHA1_OPS:
                    begin
                        sha1_on <= wbs_dat_i[0];
                        sha1_reset <= wbs_dat_i[1];
                        if (wbs_dat_i[0]) begin
                            sha1_msg_idx <= 0;
                            sha1_done <= 0;
                            sha1_digest_idx <= 0;
                        end
                        buffer_o <= {21'b0, index, sha1_done, sha1_panic, wbs_dat_i[1], wbs_dat_i[0]};
                    end
                    CTRL_MSG_IN:
                    begin
                        if (sha1_on)
                            buffer_o <= EINVAL;
                        else begin
                            buffer_o <= ACK;
                            case (sha1_msg_idx)
                                'hf : message[511:480] <= wbs_dat_i;
                                'he : message[479:448] <= wbs_dat_i;
                                'hd : message[447:416] <= wbs_dat_i;
                                'hc : message[415:384] <= wbs_dat_i;
                                'hb : message[383:352] <= wbs_dat_i;
                                'ha : message[351:320] <= wbs_dat_i;
                                'h9 : message[319:288] <= wbs_dat_i;
                                'h8 : message[287:256] <= wbs_dat_i;
                                'h7 : message[255:224] <= wbs_dat_i;
                                'h6 : message[223:192] <= wbs_dat_i;
                                'h5 : message[191:160] <= wbs_dat_i;
                                'h4 : message[159:128] <= wbs_dat_i;
                                'h3 : message[127:96] <= wbs_dat_i;
                                'h2 : message[95:64] <= wbs_dat_i;
                                'h1 : message[63:32] <= wbs_dat_i;
                                'h0 : message[31:0] <= wbs_dat_i;
                                default: begin
                                    sha1_panic <= 1'b1;
                                end
                            endcase
                            if (!transmit) begin
                                if (sha1_msg_idx == 'hf) begin
                                    sha1_on <= 1'b1;
                                    sha1_msg_idx <= 0;
                                end else
                                    sha1_msg_idx <= sha1_msg_idx + 1'b1;
                            end
                        end
                    end
                endcase
                if ((wbs_adr_i[31:0] >= BASE_ADDRESS) && (wbs_adr_i <= CTRL_SHA1_DIGEST))
                    transmit <= 1'b1;
            end
        end
    end

    sha1 sha1_compute (
        .clk(wb_clk_i),
        .reset(sha1_wire_rst),
        .on(sha1_on),
        .message_in(message),
        .digest(digest),
        .finish(finish),
        .idx(index));

    assign sha1_wire_rst = reset ? 1'b1 : sha1_reset;

    assign wbs_ack_o = reset ? 1'b0 : transmit;

    assign wbs_dat_o = reset ? 32'b0 : buffer_o;

    assign done = reset ? 1'b0 : sha1_done;

    assign irq = reset ? 1'b0: sha1_done;

endmodule
`default_nettype wire
