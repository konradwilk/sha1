module dump();
    initial begin
        $dumpfile ("wb_logic.vcd");
        $dumpvars (0, sha1_wb);
        #1;
    end
endmodule
