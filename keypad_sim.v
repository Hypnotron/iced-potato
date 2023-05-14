`ifdef SIMULATED
    `default_nettype none
    `timescale 1ns/1ps
    module keypad_sim(
            input wire [3:0] keypad_row,
            output wire [3:0] keypad_column);
        reg [15:0] keypad;
        integer key_file;
        initial begin
            key_file = $fopen("/tmp/chip8-input.raw", "rb"); 
        end
        generate
            genvar i;
            for (i = 0; i < 4; i = i + 1) begin
                assign keypad_column[i] = !keypad[{$clog2(~keypad_row), i[1:0]}];
            end
        endgenerate
        always begin
            `ifdef TAS
                #16666666
                $fread(keypad, key_file);
            `else
                #1000000
                $fclose(key_file);
                key_file = $fopen("/tmp/chip8-input.raw", "r");
                $fscanf(key_file, "%x", keypad);
            `endif
        end
    endmodule
`endif
