`default_nettype none
`timescale 1ns/1ps
module ps2_controller(
        input wire clock,
        input wire reset,
        input wire ps2_clock,
        input wire data,
        input wire [15:0] action,
        output reg [7:0] scancode,
        output reg scancode_start,
        output reg [15:0] keypad,
        output reg [15:0] signals);
    reg [11:0] rx;
    reg [2:0] ps2_clock_sync;
    reg parity;
    reg pressed;
    localparam GET_SCANCODE             = 4'h0;
    localparam GET_SCANCODE_FINISH      = 4'h1; 
    localparam DECODE_SCANCODE          = 4'h2; 
    reg [3:0] state;
    localparam CONTINUE                 = 4'h0;
    localparam DELAY                    = 4'h1;
    reg [3:0] waitstate;
    always @(posedge clock) begin
        if (!reset) begin
            rx <= 12'h800;
            ps2_clock_sync <= {3{1'b1}};
            pressed <= 1'b0;
            state <= GET_SCANCODE;
            scancode <= 8'b0;
            scancode_start <= 1'b0;
            keypad <= 16'b0;
            signals <= 16'b0;
        end else begin
            case (waitstate)
                DELAY: begin
                    waitstate <= CONTINUE;
                end
                CONTINUE: begin
                    case (state)
                        GET_SCANCODE: begin
                            ps2_clock_sync <= {ps2_clock_sync[1:0], ps2_clock};
                            if (ps2_clock_sync[2:1] == 2'b10) begin
                                rx <= {data, rx[11:1]};
                                parity <= parity ^ data;
                                if (rx[1]) begin
                                    state <= GET_SCANCODE_FINISH;
                                end
                            end
                        end
                        GET_SCANCODE_FINISH: begin
                            rx <= 12'h800;
                            if (parity) begin
                                state <= GET_SCANCODE;
                            end else begin
                                scancode <= rx[9:2];
                                scancode_start <= 1'b1;
                                waitstate <= DELAY;
                                state <= DECODE_SCANCODE;
                            end
                        end
                        DECODE_SCANCODE: begin
                            scancode_start <= 1'b0;
                            state <= GET_SCANCODE;
                            case (action[7:4])
                                4'h0: begin
                                    keypad[action[3:0]] <= pressed; 
                                    pressed <= 1'b1;
                                end
                                4'h1: begin
                                    signals[action[3:0]] <= pressed;
                                    pressed <= 1'b1;
                                end
                                4'h2: begin
                                    pressed <= 1'b0;
                                end
                            endcase
                        end
                    endcase
                end
            endcase
        end
    end
endmodule
