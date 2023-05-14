`default_nettype none
`timescale 1ns/1ps
module keypad(
        input wire clock,
        input wire reset,
        input wire [31:0] main_frequency,
        input wire [23:0] poll_frequency,
        input wire released_keys_clear,
        input wire [63:0] keymap,
        input wire [3:0] keypad_column,
        output reg [3:0] keypad_row,
        output reg [15:0] keypad_out,
        output reg [15:0] released_keys_out);
    reg signed [31:0] counter;
    reg [23:0] delay_counter;
    reg [15:0] keypad_previous;
    reg [15:0] keypad;
    reg [15:0] keypad_full;
    reg [15:0] keypad_translated;
    reg [15:0] released_keys;
    reg [15:0] released_keys_translated;
    reg [3:0] index;
    /*
    generate
        genvar i;
        for (i = 0; i < 16; i = i + 1) begin
            assign keypad_out[(keymap >> (i * 4'd4)) & 4'hf] = keypad_full[i];
            assign released_keys_out[(keymap >> (i * 4'd4)) & 4'hf] = released_keys[i];
        end
    endgenerate
    */
    localparam IDLE             = 4'h0;
    localparam WAIT             = 4'h1;
    localparam SCAN             = 4'h2;
    localparam SAVE             = 4'h3;
    localparam TRANSLATE        = 4'h4;
    localparam FINISH           = 4'h5;
    reg [3:0] state;
    always @(posedge clock) begin
        if (!reset) begin
            counter <= 32'b0;
            delay_counter <= 24'b0;
            keypad_previous <= 16'b0;
            keypad <= 16'b0;
            keypad_full <= 16'b0;
            released_keys <= 16'b0;
            index <= 4'b0;
            state <= 4'b0;
            keypad_row <= 4'b1111;
        end else begin
            if (counter < 0) begin
                counter <= counter + main_frequency - poll_frequency;
            end else begin
                counter <= counter - poll_frequency;
            end
            case (state)
                IDLE: begin
                    if (counter < 0) begin
                        keypad_row <= 4'b1110;
                        delay_counter <= 24'h400;
                        state <= WAIT;
                    end
                end
                WAIT: begin
                    delay_counter <= delay_counter - 1'b1;
                    if (delay_counter == 24'b0) begin
                        state <= SCAN;
                    end
                end
                SCAN: begin
                    `define mask (~(~keypad_column ^ keypad_previous[15:12]))
                    keypad_row <= {keypad_row[2:0], keypad_row[3]};
                    keypad_previous <= {keypad_previous[11:0], ~keypad_column};
                    keypad <= {
                            keypad[11:0],
                            keypad[15:12] & ~`mask
                          | ~keypad_column & `mask};
                    delay_counter <= 24'h400;
                    state <= WAIT;
                    if (keypad_row == 4'b0111) begin
                        keypad_row <= 4'b1111;
                        state <= SAVE;
                    end
                    `undef mask
                end
                SAVE: begin
                    released_keys <= (keypad ^ keypad_full) & keypad_full;
                    keypad_full <= keypad;
                    state <= TRANSLATE;
                end
                TRANSLATE: begin
                    keypad_translated[(keymap >> (index * 8'h4)) & 4'hf] 
                          <= keypad_full[0];
                    keypad_full <= {keypad_full[0], keypad_full[15:1]};
                    released_keys_translated[(keymap >> (index * 8'h4)) & 4'hf] 
                          <= released_keys[0];
                    released_keys <= {released_keys[0], released_keys[15:1]};
                    index <= index + 1'b1;
                    if (index == 4'hf) begin
                        state <= FINISH;
                    end
                end
                FINISH: begin
                    released_keys_out <= released_keys_translated;
                    keypad_out <= keypad_translated;
                    state <= IDLE;
                end
            endcase
            if (released_keys_clear) begin
                released_keys_out <= 16'b0;
            end
        end
    end
endmodule
