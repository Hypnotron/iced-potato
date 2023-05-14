`default_nettype none
`timescale 1ns/1ps
`include "fs.v"
`include "hypervisor_commands.v"
`include "quirks.v"
//TODO: bootrom
//TODO: check system (CHIP_8, SCHIP, XO_CHIP) before executing extended opcodes
//TODO: fix font
//TODO: more quirks
module cpu(
        input wire clock,
        input wire reset,
        input wire [15:0] instructions_per_frame,
        input wire [7:0] mm_data_in,
        input wire [31:0] vram_data_in,
        input wire [9:0] bcd_in,
        input wire [15:0] keypad,
        input wire [15:0] released_keys,
        input wire in_vblank,
        input wire [63:0] quirks,
        input wire hypervisor_busy,
        output wire sound_enable,
        output reg sound_load_pattern,
        output reg [127:0] sound_pattern_out,
        output reg [7:0] pitch_out,
        output reg pitch_start,
        output reg [15:0] mm_address,
        output reg [7:0] mm_data_out,
        output reg mm_direction, 
        output reg [31:0] vram_data_out,
        output reg [8:0] vram_address,
        output reg [1:0] vram_direction,
        output reg [1:0] vram_start,
        output reg [7:0] bcd_out,
        output reg bcd_start,
        output reg [4:0] scroll_x_low,
        output reg [5:0] scroll_y_low,
        output reg [4:0] scroll_x_high,
        output reg [5:0] scroll_y_high,
        output reg [3:0] hypervisor_opcode,
        output reg [7:0] hypervisor_game_index,
        output reg [7:0] hypervisor_previous_page,
        output reg [7:0] hypervisor_last_page,
        output reg hypervisor_parse_header,
        output reg hypervisor_execute,
        output reg released_keys_clear,
        output wire debug_out);
    integer index;
    reg [15:0] opcode;
    reg [7:0] v [15:0];
    reg [15:0] pc;
    reg [15:0] i;
    reg [3:0] offset;
    reg [3:0] immediate;
    reg skip;
    reg [15:0] sprite_slice;
    reg [4:0] sprite_row;
    reg [15:0] stack [11:0];
    reg [3:0] stack_pointer;
    reg [7:0] delay_timer;
    reg [7:0] sound_timer;
    assign sound_enable = sound_timer > 8'b0;
    reg previous_in_vblank;
    reg [8:0] alu_out;
    reg [15:0] rng;
    reg high_resolution;
    reg collision;
    reg [1:0] plane_select;
    reg draw_dual_plane;
    reg ascending;
    reg increment_i;
    wire rng_tap = rng[15] ^ rng[4] ^ rng[2] ^ rng[1];
    wire [7:0] random = rng[15:8] ^ rng[7:0];
    localparam FETCH_HIGH                       = 8'h00;
    localparam FETCH_LOW                        = 8'h01;
    localparam DECODE_LOW                       = 8'h02;
    localparam DECODE_HIGH                      = 8'h03;
    localparam EXECUTE                          = 8'h04;
    localparam STM                              = 8'h05;
    localparam LDM_PREPARE                      = 8'h06;
    localparam LDM                              = 8'h07;
    localparam DISPLAY_CLEAR                    = 8'h08;
    localparam DISPLAY_CLEAR_COLUMN_FETCH       = 8'h09;
    localparam DISPLAY_CLEAR_COLUMN_WRITE       = 8'h0a;
    localparam DISPLAY_CLEAR_ROWS               = 8'h0b;
    localparam DRAW_FETCH_LEFT                  = 8'h0c;
    localparam DRAW_FETCH_WIDE                  = 8'h0d;
    localparam DRAW_WRITE_LEFT                  = 8'h0e;
    localparam DRAW_FETCH_RIGHT                 = 8'h0f;
    localparam DRAW_WRITE_RIGHT                 = 8'h10;
    localparam DRAW_INCREMENT                   = 8'h11;
    localparam SKIP_KEY                         = 8'h12;
    localparam BCD                              = 8'h13;
    localparam ALU_FINISH                       = 8'h14;
    localparam LOAD_LONG                        = 8'h15;
    localparam AUDIO_PATTERN_LOAD_PREPARE       = 8'h16;
    localparam AUDIO_PATTERN_LOAD               = 8'h17;
    localparam SET_QUIRKS_PREPARE               = 8'h18;
    localparam SET_QUIRKS_LOAD                  = 8'h19;
    localparam SET_QUIRKS                       = 8'h1a;
    reg [7:0] state;
    localparam CONTINUE         = 4'h0;
    localparam DELAY            = 4'h1;
    localparam WAIT_READ        = 4'h2;
    localparam WAIT_WRITE       = 4'h3;
    localparam WAIT_KEY         = 4'h4;
    localparam WAIT_HYPERVISOR  = 4'h5;
    reg [3:0] waitstate;
    reg [15:0] instructions_remaining;
    wire [4:0] scroll_x = plane_select[0] ? scroll_x_low : scroll_x_high;
    wire [5:0] scroll_y = plane_select[0] ? scroll_y_low : scroll_y_high;
    assign debug_out = instructions_remaining > 16'b0;
    `ifdef SIMULATED
        generate
            genvar j;
            for (j = 0; j < 16; j = j + 1) begin: dump_registers
                initial begin
                    `ifdef DUMPVARS
                        $dumpfile("/tmp/chip8.vcd");
                        $dumpvars(0, v[j]);
                    `endif
                end
            end
        endgenerate
    `endif
    always @(posedge clock) begin
        if (!reset) begin
            opcode <= 16'h8000;
            for (index = 0; index < 16; index = index + 1) begin
                v[index] <= 8'b0;
            end
            pc <= 16'h0200;
            i <= 16'h0000;
            offset <= 4'b0;
            immediate <= 4'b0;
            skip <= 1'b0;
            sprite_slice <= 16'b0;
            sprite_row <= 5'b0;
            for (index = 0; index < 12; index = index + 1) begin
                stack[index] <= 16'b0;
            end
            stack_pointer <= 4'b0;
            delay_timer <= 8'b0;
            sound_timer <= 8'b0;
            previous_in_vblank <= 1'b0;
            alu_out <= 9'b0;
            rng <= 16'hffff;
            high_resolution <= 1'b0;
            collision <= 1'b0;
            plane_select <= 2'b01;
            draw_dual_plane <= 1'b0;
            ascending <= 1'b1;
            increment_i <= 1'b0;
            scroll_x_low <= 5'b0;
            scroll_y_low <= 6'b0;
            scroll_x_high <= 5'b0;
            scroll_y_high <= 6'b0;
            //TODO: delete commented code
            /*
            hypervisor_opcode <= 4'b0;
            hypervisor_game_index <= 8'b0;
            hypervisor_previous_page <= 8'b0;
            hypervisor_last_page <= 8'b0;
            hypervisor_parse_header <= 1'b0;
            hypervisor_execute <= 1'b0;
            */
            released_keys_clear <= 1'b1;
            state <= FETCH_HIGH;
            waitstate <= CONTINUE;
            instructions_remaining <= 16'b0;
            sound_load_pattern <= 1'b0;
            sound_pattern_out <= 128'b0;
            pitch_out <= 8'h40;
            pitch_start <= 1'b1;
        end else begin 
            if (!in_vblank && previous_in_vblank) begin
                if (delay_timer > 0) begin
                    delay_timer <= delay_timer - 1'b1;
                end
                if (sound_timer > 0) begin
                    sound_timer <= sound_timer - 1'b1;
                end
                instructions_remaining <= instructions_per_frame;
            end
            previous_in_vblank <= in_vblank;
            rng <= {rng[14:0], rng_tap};
            if (
                    waitstate == CONTINUE
                 && instructions_remaining > 16'b0
                 && !in_vblank) begin
                case (state)
                    FETCH_HIGH: begin
                        mm_address <= pc;
                        pc <= pc + 1'b1;
                        mm_direction <= 1'b0;
                        state <= FETCH_LOW;
                    end
                    FETCH_LOW: begin
                        mm_address <= pc;
                        pc <= pc + 1'b1;
                        mm_direction <= 1'b0;
                        vram_direction <= 2'b0;
                        pitch_start <= 1'b0;
                        sound_load_pattern <= 1'b0;
                        state <= DECODE_HIGH;
                    end
                    DECODE_HIGH: begin
                        mm_address <= pc;
                        opcode[15:8] <= mm_data_in;
                        state <= DECODE_LOW;
                    end
                    DECODE_LOW: begin
                        opcode[7:0] <= mm_data_in;
                        instructions_remaining <= instructions_remaining - 1'b1;
                        state <= EXECUTE;
                    end
                    EXECUTE: begin
                        state <= FETCH_LOW;
                        pc <= pc + 1'b1;
                        skip <= 1'b0;
                        if (!skip) begin
                            case (opcode[15:12])
                                4'h0: begin
                                    case (opcode[11:0])
                                        12'h0e0: begin
                                            vram_address <= 9'b0;
                                            vram_data_out <= 32'b0;
                                            vram_direction <= plane_select; 
                                            vram_start <= 2'b0;
                                            state <= DISPLAY_CLEAR;
                                        end
                                        12'h0ee: begin
                                            pc <= stack[stack_pointer - 1'b1];
                                            stack_pointer <= stack_pointer - 1'b1;
                                            state <= FETCH_HIGH;
                                        end
                                        12'h0fd: begin
                                            hypervisor_opcode <= `HYPERVISOR_READ;
                                            hypervisor_game_index <= 8'b0;
                                            hypervisor_previous_page <= 8'hff;
                                            hypervisor_last_page <= 8'hff;
                                            hypervisor_parse_header <= 1'b1;
                                            hypervisor_execute <= 1'b1;
                                            pc <= pc;
                                            waitstate <= WAIT_HYPERVISOR;
                                            state <= FETCH_HIGH;
                                        end
                                        12'h0fe: begin
                                            high_resolution <= 1'b0;
                                            if (quirks[`DISPLAY_MODESWITCH_CLEAR]) begin
                                                vram_address <= 9'b0;
                                                vram_data_out <= 32'b0;
                                                vram_direction <= 2'b11; 
                                                vram_start <= 2'b0;
                                                state <= DISPLAY_CLEAR;
                                            end
                                        end
                                        12'h0ff: begin
                                            high_resolution <= 1'b1;
                                            if (quirks[`DISPLAY_MODESWITCH_CLEAR]) begin
                                                vram_address <= 9'b0;
                                                vram_data_out <= 32'b0;
                                                vram_direction <= 2'b11; 
                                                vram_start <= 2'b0;
                                                state <= DISPLAY_CLEAR;
                                            end
                                        end
                                        12'h0fb: begin
                                            if (
                                                    draw_dual_plane
                                                 && plane_select == 2'b11) begin
                                                plane_select <= 2'b01;
                                            end
                                            if (plane_select[0]) begin
                                                scroll_x_low <= scroll_x_low - 1'b1;
                                            end else begin
                                                scroll_x_high <= scroll_x_high - 1'b1;
                                            end
                                            vram_address <= (scroll_x - 1'b1) >> 2'h2;
                                            vram_direction <= 2'b0;
                                            vram_start <= 2'b11;
                                            sprite_slice <= ~(16'hf000 >> (((scroll_x - 1'b1) & 16'h3) * 4'h4));
                                            waitstate <= DELAY;
                                            state <= DISPLAY_CLEAR_COLUMN_WRITE;
                                        end
                                        12'h0fc: begin
                                            if (
                                                    draw_dual_plane
                                                 && plane_select == 2'b11) begin
                                                plane_select <= 2'b01;
                                            end
                                            if (plane_select[0]) begin
                                                scroll_x_low <= scroll_x_low + 1'b1;
                                            end else begin
                                                scroll_x_high <= scroll_x_high + 1'b1;
                                            end
                                            vram_address <= scroll_x >> 2'h2;
                                            vram_direction <= 2'b0;
                                            vram_start <= 2'b11;
                                            sprite_slice <= ~(16'hf000 >> (scroll_x[1:0] * 4'h4));
                                            waitstate <= DELAY;
                                            state <= DISPLAY_CLEAR_COLUMN_WRITE;
                                        end
                                        default: begin
                                            case (opcode[11:4])
                                                8'h08: begin
                                                    hypervisor_opcode <= `HYPERVISOR_READ;
                                                    hypervisor_game_index <= v[opcode[3:0]];
                                                    hypervisor_previous_page <= i[15:8];
                                                    hypervisor_last_page <= i[7:0];
                                                    hypervisor_parse_header <= i == 16'hffff;
                                                    hypervisor_execute <= 1'b1;
                                                    pc <= pc;
                                                    waitstate <= WAIT_HYPERVISOR;
                                                    state <= FETCH_HIGH;
                                                end
                                                8'h09: begin
                                                    //TODO: hypervisor write
                                                end
                                                8'h0c: begin
                                                    if (
                                                            draw_dual_plane
                                                         && plane_select == 2'b11) begin
                                                        plane_select <= 2'b01;
                                                    end
                                                    if (plane_select[0]) begin
                                                        scroll_y_low <= 
                                                                scroll_y_low
                                                              - (opcode[3:0]
                                                             << (quirks[`DOUBLE_SCROLL]
                                                             && !high_resolution));
                                                    end else begin
                                                        scroll_y_high <= 
                                                                scroll_y_high
                                                              - (opcode[3:0]
                                                             << (quirks[`DOUBLE_SCROLL]
                                                             && !high_resolution));
                                                    end
                                                    sprite_row <= 5'b0;
                                                    vram_data_out <= 32'b0;
                                                    vram_address <= 
                                                            (scroll_y
                                                          - (opcode[3:0]
                                                         << (quirks[`DOUBLE_SCROLL]
                                                         && !high_resolution))
                                                          & 6'h3f) << 2'h3;
                                                    vram_direction <= plane_select[0] ? 2'b01 : 2'b10;
                                                    vram_start <= 2'b0;
                                                    state <= DISPLAY_CLEAR_ROWS;
                                                end
                                                8'h0d: begin
                                                    if (
                                                            draw_dual_plane
                                                         && plane_select == 2'b11) begin
                                                        plane_select <= 2'b01;
                                                    end
                                                    if (plane_select[0]) begin
                                                        scroll_y_low <= 
                                                                scroll_y_low
                                                              + (opcode[3:0]
                                                             << (quirks[`DOUBLE_SCROLL]
                                                             && !high_resolution));
                                                    end else begin
                                                        scroll_y_high <= 
                                                                scroll_y_high
                                                              + (opcode[3:0]
                                                             << (quirks[`DOUBLE_SCROLL]
                                                             && !high_resolution));
                                                    end
                                                    sprite_row <= 5'b0;
                                                    vram_data_out <= 32'b0;
                                                    vram_address <= 
                                                            (scroll_y
                                                          & 6'h3f) << 2'h3;
                                                    vram_direction <= plane_select[0] ? 2'b01 : 2'b10;
                                                    vram_start <= 2'b0;
                                                    state <= DISPLAY_CLEAR_ROWS;
                                                end
                                            endcase
                                        end
                                    endcase
                                end
                                4'h1: begin
                                    pc <= opcode[11:0];
                                    state <= FETCH_HIGH;
                                end
                                4'h2: begin
                                    stack[stack_pointer] <= pc;
                                    stack_pointer <= stack_pointer + 1'b1;
                                    pc <= opcode[11:0];
                                    state <= FETCH_HIGH;
                                end
                                4'h3: begin
                                    skip <= v[opcode[11:8]] == opcode[7:0];
                                end
                                4'h4: begin
                                    skip <= v[opcode[11:8]] != opcode[7:0];
                                end
                                4'h5: begin
                                    case (opcode[3:0])
                                        4'h0: begin
                                            skip <= 
                                                    v[opcode[11:8]]
                                                 == v[opcode[7:4]];
                                        end
                                        4'h2: begin
                                            ascending <= 
                                                    opcode[11:8] < opcode[7:4];
                                            offset <= opcode[11:8];
                                            immediate <= opcode[7:4];
                                            mm_address <= i - 1'b1;
                                            increment_i <= 1'b0;
                                            pc <= pc;
                                            state <= STM;
                                        end
                                        4'h3: begin
                                            ascending <= 
                                                    opcode[11:8] < opcode[7:4];
                                            offset <= opcode[11:8];
                                            immediate <= opcode[7:4];
                                            mm_address <= i;
                                            mm_direction <= 1'b0;
                                            increment_i <= 1'b0;
                                            pc <= pc;
                                            state <= LDM_PREPARE;
                                        end
                                    endcase
                                end
                                4'h6: begin
                                    v[opcode[11:8]] <= opcode[7:0];
                                end
                                4'h7: begin
                                    v[opcode[11:8]] <= v[opcode[11:8]] + opcode[7:0];
                                end
                                4'h8: begin
                                    case (opcode[3:0])
                                        4'h0: begin
                                            v[opcode[11:8]] <= v[opcode[7:4]];
                                        end
                                        4'h1: begin
                                            v[opcode[11:8]] <= 
                                                    v[opcode[11:8]]
                                                  | v[opcode[7:4]];
                                        end
                                        4'h2: begin
                                            v[opcode[11:8]] <= 
                                                    v[opcode[11:8]]
                                                  & v[opcode[7:4]];
                                        end
                                        4'h3: begin
                                            v[opcode[11:8]] <= 
                                                    v[opcode[11:8]]
                                                  ^ v[opcode[7:4]];
                                        end
                                        4'h4: begin
                                            alu_out <=
                                                    v[opcode[11:8]]
                                                  + v[opcode[7:4]];
                                            state <= ALU_FINISH;
                                        end
                                        4'h5: begin
                                            alu_out <= {
                                                    v[opcode[11:8]]
                                                 >= v[opcode[7:4]],                                                    
                                                    v[opcode[11:8]]
                                                  - v[opcode[7:4]]};
                                            state <= ALU_FINISH;
                                        end
                                        4'h6: begin
                                            if (quirks[`SHIFT_IGNORE_VY]) begin
                                                alu_out <= {
                                                        v[opcode[11:8]][0],
                                                        1'b0,
                                                        v[opcode[11:8]][7:1]};
                                            end else begin
                                                alu_out <= {
                                                        v[opcode[7:4]][0],
                                                        1'b0,
                                                        v[opcode[7:4]][7:1]};
                                            end
                                            state <= ALU_FINISH;
                                        end
                                        4'h7: begin
                                            alu_out <= {
                                                    v[opcode[7:4]]
                                                 >= v[opcode[11:8]],                                                    
                                                    v[opcode[7:4]]
                                                  - v[opcode[11:8]]};
                                            state <= ALU_FINISH;
                                        end
                                        4'he: begin
                                            if (quirks[`SHIFT_IGNORE_VY]) begin
                                                alu_out <= 
                                                        {v[opcode[11:8]], 1'b0};
                                            end else begin
                                                alu_out <= 
                                                        {v[opcode[7:4]], 1'b0};
                                            end
                                            state <= ALU_FINISH;
                                        end
                                    endcase
                                end
                                4'h9: begin
                                    skip <= v[opcode[11:8]] != v[opcode[7:4]];
                                end
                                4'ha: begin
                                    i <= {4'h0, opcode[11:0]};
                                end
                                4'hb: begin
                                    //TODO: truncate
                                    pc <=
                                            (opcode[11:0]
                                          + (quirks[`BRANCH_BXNN]
                                          ? v[opcode[11:8]]
                                          : v[4'h0])) & 16'h0fff;
                                    state <= FETCH_HIGH;
                                end
                                4'hc: begin
                                    v[opcode[11:8]] <= random & opcode[7:0];
                                end
                                4'hd: begin
                                    v[4'hf] <= 8'b0;
                                    sprite_row <= 5'b0;
                                    if (high_resolution) begin
                                        offset <=
                                                v[opcode[11:8]][3:0]
                                              + (scroll_x[1:0] << 2'h2);
                                        vram_address <=
                                                ((v[opcode[7:4]][5:0]
                                              + scroll_y
                                              & 6'h3f) << 2'h3)
                                              + ((v[opcode[11:8]][6:4]
                                              + scroll_x[4:2]
                                              + (v[opcode[11:8]][3:0]
                                              + (scroll_x[1:0] << 2'h2)
                                              > 6'hf)) & 3'h7);
                                    end else begin
                                        offset <=
                                                (v[opcode[11:8]][2:0] << 1'h1)
                                              + (scroll_x[1:0] << 2'h2);
                                        vram_address <=
                                                (((v[opcode[7:4]][4:0] << 1'h1)
                                              + scroll_y
                                              & 6'h3f) << 2'h3)
                                              + ((v[opcode[11:8]][5:3]
                                              + scroll_x[4:2]
                                              + ((v[opcode[11:8]][2:0] << 1'h1)
                                              + (scroll_x[1:0] << 2'h2)
                                              > 6'hf)) & 3'h7);
                                    end
                                    if (draw_dual_plane) begin
                                        plane_select <= 2'b01;
                                    end
                                    pc <= pc;
                                    mm_address <= i;
                                    mm_direction <= 1'b0;
                                    waitstate <= WAIT_READ;
                                    state <= DRAW_FETCH_LEFT;
                                end
                                4'he: begin
                                    case (opcode[3:0])
                                        4'he: begin
                                            skip <= keypad[v[opcode[11:8]]];
                                        end
                                        4'h1: begin
                                            skip <= !keypad[v[opcode[11:8]]];
                                        end
                                    endcase
                                    state <= FETCH_LOW;
                                end
                                4'hf: begin
                                    case (opcode[3:0])
                                        4'h0: begin
                                            case (opcode[7:4])
                                                4'h0: begin
                                                    i[15:8] <= mm_data_in;
                                                    mm_address <= pc + 1'b1;
                                                    mm_direction <= 1'b0;
                                                    waitstate <= WAIT_READ;
                                                    state <= LOAD_LONG;
                                                end
                                                4'h3: begin
                                                    i <= 
                                                        v[opcode[11:8]][3:0] * 16'd10
                                                      + `HIGH_RESOLUTION_FONT_ADDRESS;
                                                end
                                            endcase
                                        end
                                        4'h1: begin
                                            plane_select <= opcode[9:8];
                                            draw_dual_plane <= 
                                                    opcode[9:8] == 2'b11;
                                        end
                                        4'h2: begin
                                            mm_address <= i;
                                            mm_direction <= 1'b0;
                                            pc <= pc;
                                            offset <= 4'b0;
                                            state <= AUDIO_PATTERN_LOAD_PREPARE;
                                        end
                                        4'h3: begin
                                            bcd_out <= v[opcode[11:8]];
                                            bcd_start <= 1'b1;
                                            mm_address <= i - 1'b1;
                                            pc <= pc;
                                            offset <= 4'hc;
                                            state <= BCD;
                                        end
                                        4'h5: begin
                                            case (opcode[7:4])
                                                4'h1: begin
                                                    delay_timer <= v[opcode[11:8]];
                                                end
                                                4'h5: begin
                                                    ascending <= 1'b1;
                                                    offset <= 4'b0;
                                                    immediate <= opcode[11:8];
                                                    mm_address <= i - 1'b1; 
                                                    increment_i <= quirks[
                                                            `LDM_STM_INCREMENT_I];
                                                    pc <= pc;
                                                    state <= STM;
                                                end
                                                4'h6: begin
                                                    ascending <= 1'b1;
                                                    offset <= 4'b0;
                                                    immediate <= opcode[11:8];
                                                    mm_address <= i;
                                                    mm_direction <= 1'b0;
                                                    increment_i <= quirks[
                                                            `LDM_STM_INCREMENT_I];
                                                    pc <= pc;
                                                    state <= LDM_PREPARE;
                                                end
                                                4'h7: begin
                                                    ascending <= 1'b1;
                                                    offset <= 4'b0;
                                                    immediate <= opcode[11:8];
                                                    mm_address <= `FLAGS_ADDRESS - 1'b1;
                                                    increment_i <= 1'b0;
                                                    pc <= pc;
                                                    state <= STM;
                                                end
                                                4'h8: begin
                                                    ascending <= 1'b1;
                                                    offset <= 4'b0;
                                                    immediate <= opcode[11:8];
                                                    mm_address <= `FLAGS_ADDRESS;
                                                    mm_direction <= 1'b0;
                                                    increment_i <= 1'b0;
                                                    pc <= pc;
                                                    state <= LDM_PREPARE;
                                                end
                                            endcase
                                        end
                                        4'h7: begin
                                            v[opcode[11:8]] <= delay_timer;
                                        end
                                        4'h8: begin
                                            sound_timer <= v[opcode[11:8]];
                                        end
                                        4'h9: begin
                                            i <= 
                                                    v[opcode[11:8]][3:0] * 16'd5
                                                  + `LOW_RESOLUTION_FONT_ADDRESS;
                                        end
                                        4'ha: begin
                                            case (opcode[7:4])
                                                4'h0: begin
                                                    waitstate <= WAIT_KEY;
                                                end
                                                4'h3: begin
                                                    pitch_out <= v[opcode[11:8]];
                                                    pitch_start <= 1'b1;
                                                end
                                            endcase
                                        end
                                        4'he: begin
                                            i <= i + v[opcode[11:8]]; 
                                        end
                                    endcase
                                end
                            endcase
                        end else if (
                                opcode == 16'hf000
                             && quirks[`XO_CHIP]) begin
                            pc <= pc + 2'h2;
                            state <= FETCH_HIGH;
                        end
                    end
                    STM: begin
                        mm_data_out <= v[offset];
                        mm_address <= mm_address + 1'b1;
                        mm_direction <= 1'b1;
                        i <=
                                increment_i
                              ? (ascending
                              ? i + 1'b1
                              : i - 1'b1)
                              : i;
                        offset <=
                                ascending
                              ? offset + 1'b1
                              : offset - 1'b1;
                        if (offset == immediate) begin
                            state <= FETCH_HIGH;
                        end
                    end
                    LDM_PREPARE: begin
                        mm_address <= mm_address + 1'b1;
                        state <= LDM;
                    end
                    LDM: begin
                        v[offset] <= mm_data_in;
                        mm_address <= mm_address + 1'b1;
                        i <=
                                increment_i
                              ? (ascending
                              ? i + 1'b1
                              : i - 1'b1)
                              : i;
                        offset <=
                                ascending
                              ? offset + 1'b1
                              : offset - 1'b1;
                        if (offset == immediate) begin
                            state <= FETCH_HIGH;
                        end
                    end
                    DISPLAY_CLEAR: begin
                        vram_data_out <= 32'b0;
                        vram_address <= vram_address + 1'b1;
                        if (vram_address == 9'h1ff) begin
                            state <= FETCH_LOW;
                        end
                    end
                    DISPLAY_CLEAR_COLUMN_WRITE: begin
                        vram_data_out[15:0] <=
                                sprite_slice
                              & vram_data_in[15:0];
                        vram_data_out[31:16] <=
                                sprite_slice
                              & vram_data_in[31:16];
                        vram_direction <= plane_select;
                        vram_start <= 2'b0;
                        state <= DISPLAY_CLEAR_COLUMN_FETCH;
                    end
                    DISPLAY_CLEAR_COLUMN_FETCH: begin
                        vram_address <= vram_address + 4'h8;
                        vram_direction <= 2'b0;
                        vram_start <= 2'b11;
                        waitstate <= DELAY;
                        state <= DISPLAY_CLEAR_COLUMN_WRITE;
                        if (vram_address[8:3] == 6'h3f) begin
                            state <= FETCH_LOW;
                            if (draw_dual_plane) begin
                                if (plane_select == 2'b01) begin
                                    plane_select <= 2'b10;
                                    pc <= pc - 1'b1;
                                    state <= EXECUTE;
                                end else begin
                                    plane_select <= 2'b11;
                                end
                            end
                        end
                    end
                    DISPLAY_CLEAR_ROWS: begin
                        vram_address <= vram_address + 1'b1;
                        if (vram_address[2:0] == 3'h7) begin
                            sprite_row <= sprite_row + 1'b1;
                            if (
                                    sprite_row + 1'b1
                                 == opcode[3:0] 
                                 << (quirks[`DOUBLE_SCROLL]
                                 && !high_resolution)) begin
                                vram_direction <= 2'b0;
                                state <= FETCH_LOW;
                                if (draw_dual_plane) begin
                                    if (plane_select == 2'b01) begin
                                        plane_select <= 2'b10;
                                        pc <= pc - 1'b1;
                                        state <= EXECUTE;
                                    end else begin
                                        plane_select <= 2'b11;
                                    end
                                end
                            end
                        end
                    end
                    DRAW_FETCH_LEFT: begin
                        if (high_resolution) begin
                            sprite_slice <= {mm_data_in, 8'b0};
                        end else begin
                            sprite_slice <=
                                    {{2{mm_data_in[7]}},
                                    {2{mm_data_in[6]}},
                                    {2{mm_data_in[5]}},
                                    {2{mm_data_in[4]}},
                                    {2{mm_data_in[3]}},
                                    {2{mm_data_in[2]}},
                                    {2{mm_data_in[1]}},
                                    {2{mm_data_in[0]}}};
                        end
                        vram_direction <= 2'b0;
                        vram_start <= 2'b11;
                        waitstate <= DELAY;
                        state <= DRAW_WRITE_LEFT;
                        if (opcode[3:0] == 4'b0 && high_resolution) begin
                            mm_address <= mm_address + 1'b1;
                            mm_direction <= 1'b0;
                            waitstate <= WAIT_READ;
                            state <= DRAW_FETCH_WIDE;
                        end
                        if (
                                quirks[`DRAW_CLIP]
                             && sprite_row 
                              + ((v[opcode[7:4]] << !high_resolution)
                              & 6'h3f) > 7'h40) begin
                            collision <= high_resolution;
                            state <= DRAW_INCREMENT;
                        end else begin
                            collision <= 1'b0;
                        end
                    end
                    DRAW_FETCH_WIDE: begin
                        sprite_slice[7:0] <= mm_data_in;
                        state <= DRAW_WRITE_LEFT;
                    end
                    DRAW_WRITE_LEFT: begin
                        collision <= 
                                collision 
                             || (plane_select[0]
                              ? ((sprite_slice >> offset)
                              & vram_data_in[15:0]) != 16'b0
                              : 1'b0)
                             || (plane_select[1]
                              ? ((sprite_slice >> offset)
                              & vram_data_in[31:16]) != 16'b0
                              : 1'b0);
                        vram_data_out[15:0] <=
                                (sprite_slice >> offset)
                              ^ vram_data_in[15:0];
                        vram_data_out[31:16] <=
                                (sprite_slice >> offset)
                              ^ vram_data_in[31:16];
                        vram_direction <= plane_select;
                        vram_start <= 2'b0;
                        //waitstate <= DELAY;
                        state <= DRAW_FETCH_RIGHT;
                    end
                    DRAW_FETCH_RIGHT: begin
                        vram_address[2:0] <= vram_address[2:0] + 1'b1;
                        vram_direction <= 2'b0;
                        vram_start <= 2'b11;
                        if (
                                quirks[`DRAW_CLIP]
                             && (v[opcode[11:8]]
                             << !high_resolution
                              & 9'h7f) >= 9'h70) begin
                            state <= DRAW_INCREMENT;
                        end else begin
                            waitstate <= DELAY;
                            state <= DRAW_WRITE_RIGHT;
                        end
                    end
                    DRAW_WRITE_RIGHT: begin
                        collision <= 
                                collision 
                             || (plane_select[0]
                              ? ((sprite_slice << (5'd16 - offset))
                              & vram_data_in[15:0]) != 16'b0
                              : 1'b0)
                             || (plane_select[1]
                              ? ((sprite_slice << (5'd16 - offset))
                              & vram_data_in[31:16]) != 16'b0
                              : 1'b0);
                        vram_data_out[15:0] <=
                                (sprite_slice << (5'd16 - offset))
                              ^ vram_data_in[15:0];
                        vram_data_out[31:16] <=
                                (sprite_slice << (5'd16 - offset))
                              ^ vram_data_in[31:16];
                        vram_direction <= plane_select;
                        vram_start <= 2'b0;
                        //waitstate <= DELAY;
                        state <= DRAW_INCREMENT;
                    end
                    DRAW_INCREMENT: begin
                        if (high_resolution && quirks[`SCHIP]) begin
                            v[4'hf] <= v[4'hf] + collision;
                        end else begin
                            v[4'hf][0] <= v[4'hf][0] || collision;
                        end
                        vram_address <= 
                                vram_address + 4'h7
                              + (vram_address[2:0] == 3'b0 ? 4'h8 : 4'h0);
                        sprite_row <= sprite_row + 1'b1;
                        vram_direction <= 2'b0;
                        mm_direction <= 1'b0;
                        state <= DRAW_FETCH_LEFT;
                        if (
                                sprite_row + 1'b1
                             == opcode[3:0] << !high_resolution
                             || sprite_row == 4'hf
                             && opcode[3:0] == 4'b0
                             && high_resolution) begin
                            if (draw_dual_plane) begin
                                if (plane_select == 2'b01) begin
                                    plane_select <= 2'b10;
                                    sprite_row <= 5'b0;
                                    if (high_resolution) begin
                                        offset <=
                                                v[opcode[11:8]][3:0]
                                              + (scroll_x_high[1:0] << 2'h2);
                                        vram_address <=
                                                ((v[opcode[7:4]][5:0]
                                              + scroll_y_high
                                              & 6'h3f) << 2'h3)
                                              + ((v[opcode[11:8]][6:4]
                                              + scroll_x_high[4:2]
                                              + (v[opcode[11:8]][3:0]
                                              + (scroll_x_high[1:0] << 2'h2)
                                              > 6'hf)) & 3'h7);
                                    end else begin
                                        offset <=
                                                (v[opcode[11:8]][2:0] << 1'h1)
                                              + (scroll_x_high[1:0] << 2'h2);
                                        vram_address <=
                                                (((v[opcode[7:4]][4:0] << 1'h1)
                                              + scroll_y_high
                                              & 6'h3f) << 2'h3)
                                              + ((v[opcode[11:8]][5:3]
                                              + scroll_x_high[4:2]
                                              + ((v[opcode[11:8]][2:0] << 1'h1)
                                              + (scroll_x_high[1:0] << 2'h2)
                                              > 6'hf)) & 3'h7);
                                    end
                                    mm_address <= mm_address + 1'b1;
                                    waitstate <= WAIT_READ;
                                end else begin
                                    plane_select <= 2'b11;
                                    state <= FETCH_HIGH;
                                end
                            end else begin
                                state <= FETCH_HIGH;
                            end
                        end
                        if (sprite_row[0] || high_resolution) begin
                            waitstate <= WAIT_READ;
                            mm_address <= mm_address + 1'b1;
                        end
                    end
                    BCD: begin
                        if (offset != 4'hc) begin
                            mm_data_out <= (bcd_in >> offset) & 8'h0f;
                            mm_address <= mm_address + 1'b1;
                            mm_direction <= 1'b1;
                            if (offset == 4'b0) begin
                                state <= FETCH_HIGH;
                            end
                        end
                        offset <= offset - 4'h4;
                    end
                    ALU_FINISH: begin
                        if (quirks[`ALU_VF_BEFORE_VX]) begin
                            v[4'hf] <= {7'b0, alu_out[8]};
                            v[opcode[11:8]] <= alu_out[7:0];
                        end else begin
                            v[opcode[11:8]] <= alu_out[7:0];
                            v[4'hf] <= {7'b0, alu_out[8]};
                        end
                        state <= FETCH_LOW;
                    end
                    LOAD_LONG: begin
                        i[7:0] <= mm_data_in;
                        pc <= pc + 1'b1;
                        state <= FETCH_HIGH;
                    end
                    AUDIO_PATTERN_LOAD_PREPARE: begin
                        mm_address <= mm_address + 1'b1;
                        state <= AUDIO_PATTERN_LOAD;
                    end
                    AUDIO_PATTERN_LOAD: begin
                        sound_pattern_out <= {
                                sound_pattern_out[119:0], mm_data_in};
                        mm_address <= mm_address + 1'b1;
                        offset <= offset + 1'b1;
                        if (offset == 4'hf) begin
                            sound_load_pattern <= 1'b1;
                            state <= FETCH_HIGH;
                        end
                    end
                    /*
                    SET_QUIRKS_PREPARE: begin
                        mm_address <= `QUIRKS_ADDRESS;
                        offset <= `QUIRKS_LENGTH;
                        state <= SET_QUIRKS_LOAD; 
                    end
                    SET_QUIRKS_LOAD: begin
                        quirks <= {quirks[55:0], mm_data_in};
                        mm_address <= mm_address + 1'b1;
                        offset <= offset - 1'b1;
                        if (offset == 8'b0) begin
                            state <= SET_QUIRKS;
                        end
                    end
                    SET_QUIRKS: begin
                        plane_select <= quirks[`XO_CHIP] ? 2'b01 : 2'b11;
                        draw_dual_plane <= 1'b0;
                        state <= FETCH_HIGH;
                    end
                    */
                endcase
            end else begin
                case (waitstate)
                    DELAY: begin
                        waitstate <= CONTINUE;
                    end
                    WAIT_READ: begin
                        waitstate <= CONTINUE;
                    end
                    WAIT_WRITE: begin
                        mm_direction <= 1'b0;
                        waitstate <= CONTINUE;
                    end
                    WAIT_KEY: begin
                        released_keys_clear <= 1'b0;
                        if (released_keys != 16'b0) begin
                            v[opcode[11:8]] <= {
                                    4'b0,
                                    released_keys[0]
                                  ? 4'h0
                                  : released_keys[1]
                                  ? 4'h1
                                  : released_keys[2]
                                  ? 4'h2
                                  : released_keys[3]
                                  ? 4'h3
                                  : released_keys[4]
                                  ? 4'h4
                                  : released_keys[5]
                                  ? 4'h5
                                  : released_keys[6]
                                  ? 4'h6
                                  : released_keys[7]
                                  ? 4'h7
                                  : released_keys[8]
                                  ? 4'h8
                                  : released_keys[9]
                                  ? 4'h9
                                  : released_keys[10]
                                  ? 4'ha
                                  : released_keys[11]
                                  ? 4'hb
                                  : released_keys[12]
                                  ? 4'hc
                                  : released_keys[13]
                                  ? 4'hd
                                  : released_keys[14]
                                  ? 4'he
                                  : 4'hf};
                            released_keys_clear <= 1'b1;
                            waitstate <= CONTINUE;
                        end
                    end
                    WAIT_HYPERVISOR: begin
                        hypervisor_execute <= 1'b0;
                        if (!hypervisor_execute && !hypervisor_busy) begin
                            waitstate <= CONTINUE;
                        end
                    end
                endcase
            end
        end
    end
endmodule
