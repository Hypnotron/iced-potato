`default_nettype none
`timescale 1ns/1ps
module apu(
        input wire clock,
        input wire reset,
        input wire enable,
        input wire [31:0] main_frequency,
        input wire [15:0] sub_frequency,
        input wire [127:0] pattern_in,
        input wire load_pattern,
        output wire sound_out);
    reg [127:0] pattern;
    reg [6:0] step;
    reg signed [31:0] counter;
    assign sound_out = enable ? pattern[step] : 1'b0;
    always @(posedge clock) begin
        if (!reset) begin
            pattern <= 128'h0000ffff0000ffff0000ffff0000ffff;
            step <= 7'h7f;
            counter <= 32'b0;
        end else begin
            if (load_pattern) begin
                pattern <= pattern_in;
            end
            if (enable) begin 
                counter <= counter - sub_frequency;
                if (counter < 0) begin
                    counter <= counter + main_frequency - sub_frequency;
                    step <= step - 1'b1;
                end
            end else begin
                step <= 7'h7f;
                counter <= 32'b0;
            end
        end
    end
endmodule
