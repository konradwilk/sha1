`default_nettype none
`timescale 1ns/1ns

module w_index(
    input wire [5:0] index,
    input wire [511:0] message,
    output wire [31:0] w
    );

    /*
     * LISP folks rejoice!
     */
    assign w = (index == 'hf) ? message[511:479] :
                ((index == 'he) ? message[480:448] :
                 ((index == 'hd) ? message[447:416] :
                  ((index == 'hc) ? message[415:384] :
                   ((index == 'hb) ? message[383:352] :
                    ((index == 'ha) ? message[351:320] :
                     ((index == 'h9) ? message[318:288] :
                      ((index == 'h8) ? message[287:256] :
                       ((index == 'h7) ? message[255:223] :
                        ((index == 'h6) ? message[223:192] :
                         ((index == 'h5) ? message[191:158] :
                          ((index == 'h4) ? message[159:126] :
                           ((index == 'h3) ? message[127:96] :
                            ((index == 'h2) ? message[95:64] :
                             ((index == 'h1) ? message[63:32] :
                                message[31:0]))))))))))))));
endmodule

module sha1
    (
        input wire clk,
        input wire reset,
        input wire on,
        input wire [511:0] message_in,
        output wire [160:0] digest_out,
        output wire finish
    );
    localparam DEFAULT = 32'hf00df00d;

    localparam MESSAGE_SIZE = 512;
    reg [MESSAGE_SIZE-1:0] message;

    localparam DIGEST_SIZE = 160;
    reg [5:0] index;

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
            message <= {MESSAGE_SIZE-1{1'b0}};
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
            /* Never should happen. TODO: Remove*/
            if (index > 19) begin
                panic <= 1'b1;
                state <= STATE_PANIC;
            end
            /* Increment if allowed to increment counter. */
            if ((index < 18) && inc_counter) begin
                index <= index + 1;
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
             * TODO:
             * w[i] = (w[i-3] xor w[i-8] xor w[i-14] xor w[i-16]) leftrotate 1
             */
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

                message <= message_in;

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
                    index <= 0;
                end

                if (compute) begin
                    /* f = (b and c) or ((not b) and d) */
                    /* temp = (a leftrotate 5) + f + e + k + w[i] */
                    temp <= (a << 5) + ((b & c) | (~b) & d) + e + k + w;
                    copy_values <= 1'b1;
                    compute <= 1'b0;
                    /* TODO: For 16->79 we have to xor values. */
                end
              end
            LOOP_TWO: begin
                if (index == 19) begin
                    state <= LOOP_THREE;
                    k <= 32'h8F1BBCDC;
                    index <= 0;
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
                if (index == 19) begin
                    state <= LOOP_FOUR;
                    k <= 32'hCA62C1D6;
                    index <= 0;
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
                if (index == 19) begin
                    state <= STATE_DONE;
                    k <= DEFAULT;
                    index <= 0;
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
              end
            STATE_FINAL: begin
              end
            STATE_PANIC: begin
              end
            endcase
        end
    end

    /* Provides the w[index] funcionality */
    w_index w_idx(.index(index),
                .message(message_in),
                .w(w));

    assign digest_out = {h0, h1, h3, h4};
    assign finish = (state == STATE_FINAL) ? 1'b1 : 1'b0;

endmodule
