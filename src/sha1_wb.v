`default_nettype none
`timescale 1ns/1ns
`ifdef FORMAL
    `define MPRJ_IO_PADS 38
`endif
`ifdef VERILATOR
    `define MPRJ_IO_PADS 38
`endif

module sha1_wb #(
    parameter    [31:0] BASE_ADDRESS   = 32'h30000024
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
    reg sha1_panic;
    reg sha1_done;
    reg [2:0] sha1_digest_idx;
    reg [5:0] sha1_loop_idx;
    reg [6:0] sha1_msg_idx;
    reg [159:0] sha1_digest;
    reg [511:0] sha1_message;
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
            sha1_digest <= 0;
            sha1_message <= 0;
            sha1_done <= 0;
            sha1_reset <= 0;
            sha1_loop_idx <= 0;
            sha1_on <= 0;
	    end else begin
		    if (transmit)
			    transmit <= 1'b0;

            if (sha1_reset)
                sha1_reset <= 1'b0;
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
                        buffer_o <= {22'b0, sha1_loop_idx, sha1_done, sha1_panic, sha1_reset, sha1_on};
				    CTRL_SHA1_DIGEST:
                    begin
                         if (sha1_done) begin
                                case (sha1_digest_idx)
                                        'h0:
                                                buffer_o <= sha1_digest[31:0];
                                        'h1:
                                                buffer_o <= sha1_digest[63:32];
                                        'h2:
                                                buffer_o <= sha1_digest[95:64];
                                        'h3:
                                                buffer_o <= sha1_digest[127:96];
                                        'h4:
                                                buffer_o <= sha1_digest[159:128];
                                        default:
                                                sha1_panic <= 1'b1;
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
                if (wbs_adr_i[31:8] == 'h300000)
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
                            buffer_o <= {22'b0, sha1_loop_idx, sha1_done, sha1_panic, wbs_dat_i[1], wbs_dat_i[0]};
                    end
                    CTRL_MSG_IN:
                    begin
                        if (sha1_on)
                            buffer_o <= EINVAL;
                        else begin
                          buffer_o <= ACK;
                          case (sha1_msg_idx)
                            'hf : sha1_message[511:480] <= wbs_dat_i;
                            'he : sha1_message[479:448] <= wbs_dat_i;
                            'hd : sha1_message[447:416] <= wbs_dat_i;
                            'hc : sha1_message[415:384] <= wbs_dat_i;
                            'hb : sha1_message[383:352] <= wbs_dat_i;
                            'ha : sha1_message[351:320] <= wbs_dat_i;
                            'h9 : sha1_message[319:288] <= wbs_dat_i;
                            'h8 : sha1_message[287:256] <= wbs_dat_i;
                            'h7 : sha1_message[255:224] <= wbs_dat_i;
                            'h6 : sha1_message[223:192] <= wbs_dat_i;
                            'h5 : sha1_message[191:160] <= wbs_dat_i;
                            'h4 : sha1_message[159:128] <= wbs_dat_i;
                            'h3 : sha1_message[127:96] <= wbs_dat_i;
                            'h2 : sha1_message[95:64] <= wbs_dat_i;
                            'h1 : sha1_message[63:32] <= wbs_dat_i;
                            'h0 : sha1_message[31:0] <= wbs_dat_i;
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
                if (wbs_adr_i[31:8] == 'h300000)
                    transmit <= 1'b1;
		     end
	     end
     end

     assign wbs_ack_o = reset ? 1'b0 : transmit;

    assign wbs_dat_o = reset ? 32'b0 : buffer_o;

    assign done = reset ? 1'b0 : sha1_done;

    assign irq = reset ? 1'b0: sha1_done;

endmodule
`default_nettype wire
