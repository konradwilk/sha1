`default_nettype none
`timescale 1ns/1ns

module sha1
    (
        input wire clk,
        input wire reset,
        input wire on,
        input wire [511:0] message_in,
        output wire [159:0] digest_out,
        output wire finish,
        output wire [5:0] idx
    );
    localparam DEFAULT = 32'hf00df00d;

    localparam MESSAGE_SIZE = 512;
    reg [32:0] message[79:0];

    localparam DIGEST_SIZE = 160;
    reg [6:0] index;

    localparam STATE_INIT   = 0;
    localparam STATE_START  = 1;
    localparam LOOP_ONE     = 2; /* Really  0 <= i <= 19 */
    localparam LOOP_TWO     = 3; /*         20        39 */
    localparam LOOP_THREE   = 4; /*         40        59 */
    localparam LOOP_FOUR    = 5; /*         60        79 */
    localparam STATE_DONE   = 6;
    localparam STATE_FINAL  = 7;
    localparam STATE_PANIC  = 8;
    reg [4:0] state;

    wire [31:0] w;

    reg [31:0] a;
    reg [31:0] a_old;
    reg [31:0] b;
    reg [31:0] b_old;
    reg [31:0] c;
    reg [31:0] c_old;
    reg [31:0] d;
    reg [31:0] d_old;
    reg [31:0] e;
    reg [31:0] e_old;

    reg [31:0] k;
    reg [31:0] f;
    reg [31:0] temp;
    reg [31:0] temp_old;

    reg [31:0] h0;
    reg [31:0] h1;
    reg [31:0] h2;
    reg [31:0] h3;
    reg [31:0] h4;

    reg panic;
    reg inc_counter;
    reg copy_values;
    reg compute;
    always @(posedge clk) begin
        if (reset) begin
            index <= 0;
            state <= STATE_INIT;
            message[0] <= {MESSAGE_SIZE-1{1'b0}};
            /* TODO: Should they have better pre-canned values? */
            a <= DEFAULT;
            b <= DEFAULT;
            c <= DEFAULT;
            d <= DEFAULT;
            e <= DEFAULT;
            k <= DEFAULT;
            h0 <= DEFAULT;
            h1 <= DEFAULT;
            h2 <= DEFAULT;
            h3 <= DEFAULT;
            h4 <= DEFAULT;
            temp <= DEFAULT;
            a_old <= DEFAULT;
            b_old <= DEFAULT;
            c_old <= DEFAULT;
            d_old <= DEFAULT;
            e_old <= DEFAULT;
            index <= 0;
            panic <= 0;
            inc_counter <= 1'b0;
            copy_values <= 1'b0;
            compute <= 1'b0;
        end else begin
            /* We are running and someone turned it off. */
            if ((index > 1) && !on)
                state <= STATE_INIT;

            /* Never should happen. TODO: Remove*/
            if (index > 79) begin
                panic <= 1'b1;
                state <= STATE_PANIC;
            end
            /* Increment if allowed to increment counter. */
            if (inc_counter) begin
                index <= index + 1'b1;
                inc_counter <= 1'b0;
            end
            /*
             * Every LOOP_ call ends up with copying the data, so
             * make it generic
             */
            if (compute) begin
                a_old <= a;
                b_old <= b;
                c_old <= c;
                d_old <= d;
            end
            if (copy_values) begin
                e <= d_old;
                d <= c_old;
                c <= b_old << 30; /* TODO: Does this even work in one clock ? */
                b <= a_old;
                a <= temp;
                copy_values <= 1'b0;
                compute <= 1'b1;
                inc_counter <= 1'b1;
            end
            /*
             * For t = 16 to 79
             * w[i] = (w[i-3] xor w[i-8] xor w[i-14] xor w[i-16]) leftrotate 1
             *
             * This means we need this ready before we get to index=16 hence
             * the +1 adjustment for every offset.
             */
            if (index >= 15) begin
                message[index+1] <= (w[index-3+1] ^ w[index-8+1] ^ w[index-14+1] ^ w[index-16+1]) << 1;
            end
            case (state)
            STATE_INIT: begin
                if (on)
                   state <= STATE_START;
                else
                   state <= STATE_INIT;
                end
            STATE_START: begin
                a <= 32'h67452301;
                h0 <= 32'h67452301;
                b <= 32'hEFCDAB89;
                h1 <= 32'hEFCDAB89;
                c <= 32'h98BADCFE;
                h2 <= 32'h98BADCFE;
                d <= 32'h10325476;
                h3 <=  32'h10325476;
                e <= 32'hC3D2E1F0;
                h4 <= 32'hC3D2E1F0;

                message[79] <= 0;
                message[78] <= 0;
                message[77] <= 0;
                message[76] <= 0;
                message[75] <= 0;
                message[74] <= 0;
                message[73] <= 0;
                message[72] <= 0;
                message[71] <= 0;
                message[70] <= 0;
                message[69] <= 0;
                message[68] <= 0;
                message[67] <= 0;
                message[66] <= 0;
                message[65] <= 0;
                message[64] <= 0;
                message[63] <= 0;
                message[62] <= 0;
                message[61] <= 0;
                message[60] <= 0;
                message[59] <= 0;
                message[58] <= 0;
                message[57] <= 0;
                message[56] <= 0;
                message[55] <= 0;
                message[54] <= 0;
                message[53] <= 0;
                message[52] <= 0;
                message[51] <= 0;
                message[50] <= 0;
                message[49] <= 0;
                message[48] <= 0;
                message[47] <= 0;
                message[46] <= 0;
                message[45] <= 0;
                message[44] <= 0;
                message[43] <= 0;
                message[42] <= 0;
                message[41] <= 0;
                message[40] <= 0;
                message[39] <= 0;
                message[38] <= 0;
                message[37] <= 0;
                message[36] <= 0;
                message[35] <= 0;
                message[34] <= 0;
                message[33] <= 0;
                message[32] <= 0;
                message[31] <= 0;
                message[30] <= 0;
                message[29] <= 0;
                message[28] <= 0;
                message[27] <= 0;
                message[26] <= 0;
                message[25] <= 0;
                message[24] <= 0;
                message[23] <= 0;
                message[22] <= 0;
                message[21] <= 0;
                message[20] <= 0;
                message[19] <= 0;
                message[18] <= 0;
                message[17] <= 0;
                message[16] <= message_in[511:479];
                message[15] <= message_in[480:448];
                message[14] <= message_in[447:416];
                message[13] <= message_in[415:384];
                message[12] <= message_in[383:352];
                message[11] <= message_in[351:320];
                message[10] <= message_in[319:288];
                message[9] <= message_in[287:256];
                message[8] <= message_in[255:223];
                message[7] <= message_in[223:192];
                message[6] <= message_in[191:158];
                message[5] <= message_in[159:126];
                message[4] <= message_in[159:126];
                message[3] <= message_in[127:96];
                message[2] <= message_in[95:64];
                message[1] <= message_in[63:32];
                message[0] <= message_in[31:0];

                state <= LOOP_ONE;
                k = 32'h5A827999;
                index <= 0;
                inc_counter <= 1'b1;
                compute <= 1'b1;
                copy_values <= 1'b0;
            end

            LOOP_ONE: begin
                if (index == 19) begin
                    state <= LOOP_TWO;
                    k <= 32'h6ED9EBA1;
                end

                if (compute) begin
                    /* f = (b and c) or ((not b) and d) */
                    /* temp = (a leftrotate 5) + f + e + k + w[i] */
                    temp <= (a << 5) + ((b & c) | (~b) & d) + e + k + w;
                    copy_values <= 1'b1;
                    compute <= 1'b0;
                end
              end
            LOOP_TWO: begin
                if (index == 39) begin
                    state <= LOOP_THREE;
                    k <= 32'h8F1BBCDC;
                end
                if (compute) begin
                    /* f = b xor c xor d */
                    /* temp = (a leftrotate 5) + f + e + k + w[i] */
                    temp <= (a << 5) + (b ^ c ^ d) + e + k + w;
                    copy_values <= 1'b1;
                    compute <= 1'b0;
                end
              end
            LOOP_THREE: begin
                if (index == 59) begin
                    state <= LOOP_FOUR;
                    k <= 32'hCA62C1D6;
                end
                if (compute) begin
                    /* f = (b and c) or (b and d) or (c and d) */
                    /* temp = (a leftrotate 5) + f + e + k + w[i] */
                    temp <= (a << 5) + ((b & c) | (b & d) | (c & d)) + e + k + w;
                    copy_values <= 1'b1;
                    compute <= 1'b0;
                end
              end
            LOOP_FOUR: begin
                if (index == 79) begin
                    state <= STATE_DONE;
                    k <= DEFAULT;
                end
                if (compute) begin
                    /* f = b xor c xor d
                    /* temp = (a leftrotate 5) + f + e + k + w[i] */
                    temp <= (a << 5) + (b ^ c ^ d) + e + k + w;
                    copy_values <= 1'b1;
                    compute <= 1'b0;
                end
              end
            STATE_DONE: begin
                h0 <= h0 + a;
                h1 <= h1 + b;
                h2 <= h2 + c;
                h3 <= h3 + d;
                h4 <= h4 + e;
                state <= STATE_FINAL;
                index <= 0;
                copy_values <= 1'b0;
                compute <= 1'b0;
                inc_counter <= 1'b0;
              end
            STATE_FINAL: begin
               if (!on)
                  state <= STATE_INIT;
              end
            STATE_PANIC: begin
              end
            endcase
        end
    end

    /* Provides the w[index] funcionality */
    assign w = message[index];

    assign digest_out = {h0, h1, h3, h4};
    assign finish = (state == STATE_FINAL) ? 1'b1 : 1'b0;

    assign idx = index;
endmodule
