module dump();
    initial begin
        $dumpfile ("sha1.vcd");
        $dumpvars (0, sha1);
        #1;
    end
endmodule
