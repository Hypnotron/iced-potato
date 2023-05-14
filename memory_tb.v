`ifdef SIMULATED
    `default_nettype none
    `timescale 1ns/1ps

    module memory_tb();
        initial begin
            $dumpfile("/tmp/memory.vcd");
            $dumpvars;
        end

        wire [7:0] cpu_data_out;
        wire cpu_ready;

        reg clock = 1;
        reg [15:0] cpu_address = 8;
        reg [7:0] cpu_data_in = 0;
        reg cpu_direction = 0;
        reg cpu_start = 0;
        cpu_memory test_cpu_memory(
                .clock(clock),
                .address(cpu_address),
                .data_in(cpu_data_in),
                .direction(cpu_direction),
                .start(cpu_start),
                .data_out(cpu_data_out),
                .ready(cpu_ready));
        always begin
            #0.04167
            clock <= 1;
            cpu_address <= cpu_address + 1; 
            cpu_data_in <= cpu_address[5:0] * 3;
            cpu_direction <= 1'b1;
            #0.04167
            clock <= 0;
            #0.04167
            clock <= 1;
            cpu_direction <= 1'b0;
            cpu_start <= 1'b1;
            #0.04167
            clock <= 0;
            #0.04167
            clock <= 1;
            #0.04167
            clock <= 0;
            #0.04167
            clock <= 1;
            #0.04167
            clock <= 0;
            #0.04167
            clock <= 1;
            cpu_start <= 1'b0;
            #0.04167
            clock <= 0;
        end
    endmodule
`endif
