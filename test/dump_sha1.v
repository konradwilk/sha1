module dump();
    initial begin
        $dumpfile ("sha1.vcd");
        $dumpvars (0, sha1_wb);
        #1;
    end
endmodule
