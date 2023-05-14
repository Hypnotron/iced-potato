`default_nettype none
`timescale 1ns/1ps
`include "flash_commands.v"
`include "fs.v"
`include "hypervisor_commands.v"
module hypervisor(
        input wire clock,
        input wire reset_user,
        input wire bypass_flash,
        input wire [7:0] bram_ipl_data_in,
        input wire flash_data_in,
        input wire [3:0] cpu_opcode,
        input wire [7:0] cpu_game_index,
        input wire [7:0] cpu_previous_page,
        input wire [7:0] cpu_last_page,
        input wire cpu_parse_header,
        input wire cpu_execute,
        output wire reset,
        output reg [15:0] mm_address,
        output reg [7:0] mm_data_out,
        output reg mm_control,
        output reg [11:0] bram_ipl_address,
        output reg bram_ipl_start,
        output reg flash_clock,
        output reg flash_select,
        output reg flash_data_out,
        output reg cpu_busy,
        output reg [63:0] quirks,
        output reg [63:0] keymap,
        output reg [15:0] palette,
        output reg [15:0] instructions_per_frame,
        output wire debug_out);
    reg [31:0] warm_up_counter = 32'b0;
    reg booted = 1'b0;
    reg enable_reset = 1'b1;
    reg [0:31] spi_tx = 32'b0;
    reg [31:0] spi_rx = 32'b0;
    reg [7:0] spi_bit_counter = 8'b0;
    reg flash_select_after_transfer = 1'b0;
    reg [7:0] game_index = 8'b0;
    reg [7:0] last_page = 8'h01;
    reg parse_header = 1'b1;
    reg [31:0] delay_counter = 32'b0;
    //active low reset:
    assign reset = !((state != BOOTED || !reset_user) && enable_reset);
    assign debug_out = flash_data_in ^ !reset;
    initial begin
        flash_clock = 1'b0;
        flash_select = 1'b1;
        flash_data_out = 1'b0;
        cpu_busy = 1'b0;
    end
    localparam                 WARM_UP = 8'h00;
    localparam                  BOOTED = 8'h01;
    localparam           LOAD_BRAM_IPL = 8'h02;
    localparam      LOAD_GAME_READ_FST = 8'h03;
    localparam       LOAD_GAME_PREPARE = 8'h04;
    localparam               LOAD_GAME = 8'h05;
    localparam ZEROFILL_MEMORY_PREPARE = 8'h06;
    localparam         ZEROFILL_MEMORY = 8'h07;
    localparam        LOAD_GAME_FINISH = 8'h08;
    localparam          POWER_UP_FLASH = 8'h09;
    localparam    POWER_UP_FLASH_DELAY = 8'h0a;
    reg [7:0] state = 8'b0;
    localparam              CONTINUE = 4'h0;
    localparam                 DELAY = 4'h1;
    localparam              WAIT_SPI = 4'h2;
    reg [3:0] waitstate = 4'b0;
    localparam                  IDLE = 4'h0;
    localparam            TRANSFER_0 = 4'h1;
    localparam            TRANSFER_1 = 4'h2;
    localparam            TRANSFER_2 = 4'h3;
    localparam            TRANSFER_3 = 4'h4;
    reg [3:0] spi_state = 4'b0;
    always @(posedge clock) begin
        case (spi_state)
            TRANSFER_0: begin
                flash_data_out <= spi_tx[0];
                spi_tx <= {spi_tx[1:31], 1'b0};
                spi_state <= TRANSFER_1;
            end
            TRANSFER_1: begin
                flash_clock <= 1'b1;
                spi_state <= TRANSFER_2;
            end
            TRANSFER_2: begin
                spi_rx <= {spi_rx[30:0], flash_data_in};
                spi_bit_counter <= spi_bit_counter - 1'b1;
                spi_state <= TRANSFER_3;
            end
            TRANSFER_3: begin
                flash_clock <= 1'b0;
                spi_state <= TRANSFER_0;
                if (spi_bit_counter == 8'b0) begin
                    spi_state <= IDLE;
                end
            end
        endcase
        case (waitstate)
            CONTINUE: begin
                case (state)
                    WARM_UP: begin
                        warm_up_counter <= warm_up_counter + 1'b1;
                        if (warm_up_counter[19] && reset_user) begin
                            if (bypass_flash) begin
                                mm_address <= 16'hffff;
                                mm_control <= 1'b1;
                                bram_ipl_address <= 12'b0;
                                bram_ipl_start <= 1'b1;
                                state <= LOAD_BRAM_IPL;
                            end else begin
                                mm_address <= 16'hffff;
                                mm_control <= 1'b1;
                                game_index <= 8'b0;
                                state <= POWER_UP_FLASH;
                            end
                        end
                    end
                    LOAD_BRAM_IPL: begin
                        bram_ipl_address <= bram_ipl_address + 1'b1;
                        if (bram_ipl_address != 12'b0) begin
                            mm_data_out <= bram_ipl_data_in; 
                            mm_address <= mm_address + 1'b1;
                            if (mm_address == 16'h1000) begin
                                mm_control <= 1'b0;
                                bram_ipl_start <= 1'b0;
                                state <= BOOTED;
                            end
                        end
                    end
                    POWER_UP_FLASH: begin
                        spi_tx[0:7] <= `RELEASE_POWER_DOWN;
                        spi_bit_counter <= 8'd8;
                        spi_state <= TRANSFER_0;
                        flash_select <= 1'b0;
                        flash_select_after_transfer <= 1'b1;
                        waitstate <= WAIT_SPI;
                        state <= POWER_UP_FLASH_DELAY;
                    end
                    POWER_UP_FLASH_DELAY: begin
                        delay_counter <= 8'h40;
                        waitstate <= DELAY;
                        state <= LOAD_GAME_READ_FST;
                    end
                    LOAD_GAME_READ_FST: begin
                        spi_tx[0:7] <= `FLASH_READ;
                        spi_tx[8:31] <= 24'h100000 + game_index * 2;
                        spi_bit_counter <= 8'd48;
                        spi_state <= TRANSFER_0;
                        flash_select <= 1'b0;
                        flash_select_after_transfer <= 1'b1;
                        waitstate <= WAIT_SPI;
                        state <= LOAD_GAME_PREPARE;
                    end
                    LOAD_GAME_PREPARE: begin
                        spi_tx[0:7] <= `FLASH_READ;
                        spi_tx[8:31] <= 24'h100000 + spi_rx[15:0] * 256;
                        spi_bit_counter <= 8'd40;
                        spi_state <= TRANSFER_0;
                        flash_select <= 1'b0;
                        flash_select_after_transfer <= 1'b0;
                        waitstate <= WAIT_SPI;
                        state <= LOAD_GAME;
                    end
                    LOAD_GAME: begin
                        mm_data_out <= spi_rx[7:0];
                        mm_address <= mm_address + 1'b1;
                        if (mm_address == {last_page, 8'hfe}) begin
                            if (parse_header && quirks[`MEMORY_ZEROFILL]) begin
                                state <= ZEROFILL_MEMORY_PREPARE;
                            end else begin
                                state <= LOAD_GAME_FINISH;
                            end
                        end else begin
                            spi_bit_counter <= 8'd8;
                            flash_clock <= 1'b1;
                            spi_state <= TRANSFER_2;
                            waitstate <= WAIT_SPI;
                        end
                        if (parse_header) begin
                            if (
                                    mm_address + 1'b1 >= `QUIRKS_ADDRESS
                                 && mm_address + 1'b1 < `QUIRKS_ADDRESS 
                                                      + `QUIRKS_LENGTH) begin
                                quirks <= {quirks[55:0], spi_rx[7:0]};
                            end
                            if (
                                    mm_address + 1'b1 >= `KEYMAP_ADDRESS
                                 && mm_address + 1'b1 < `KEYMAP_ADDRESS 
                                                      + `KEYMAP_LENGTH) begin
                                keymap <= {keymap[55:0], spi_rx[7:0]};
                            end
                            if (
                                    mm_address + 1'b1 >= `PALETTE_ADDRESS
                                 && mm_address + 1'b1 < `PALETTE_ADDRESS 
                                                      + `PALETTE_LENGTH) begin
                                palette <= {palette[7:0], spi_rx[7:0]};
                            end
                            if (
                                    mm_address + 1'b1 >= `INSTRUCTIONS_PER_FRAME_ADDRESS
                                 && mm_address + 1'b1 < `INSTRUCTIONS_PER_FRAME_ADDRESS
                                                      + `INSTRUCTIONS_PER_FRAME_LENGTH) begin
                                instructions_per_frame <= {instructions_per_frame[7:0], spi_rx[7:0]};
                            end
                            if (
                                    mm_address + 1'b1 >= `LAST_PAGE_ADDRESS
                                 && mm_address + 1'b1 < `LAST_PAGE_ADDRESS
                                                      + `LAST_PAGE_LENGTH) begin
                                last_page <= spi_rx[7:0];
                            end
                        end
                    end
                    ZEROFILL_MEMORY_PREPARE: begin
                        mm_data_out <= 8'b0;
                        mm_address <= mm_address + 1'b1;
                        mm_control <= 1'b1;
                        flash_select <= 1'b1;
                        state <= ZEROFILL_MEMORY;
                    end
                    ZEROFILL_MEMORY: begin
                        mm_address <= mm_address + 1'b1;
                        if (mm_address == 16'hfffe) begin
                            state <= LOAD_GAME_FINISH;
                        end
                    end
                    LOAD_GAME_FINISH: begin
                        mm_control <= 1'b0;
                        flash_select <= 1'b1;
                        enable_reset <= 1'b1;
                        state <= BOOTED;
                    end
                    BOOTED: begin
                        if (!reset_user) begin
                            state <= WARM_UP;
                        end else if (cpu_execute) begin
                            case (cpu_opcode)
                                `HYPERVISOR_READ: begin
                                    game_index <= cpu_game_index;
                                    mm_address <= {cpu_previous_page, 8'hff};
                                    mm_control <= 1'b1;
                                    last_page <= cpu_last_page;
                                    parse_header <= cpu_parse_header;
                                    enable_reset <= cpu_parse_header;
                                    cpu_busy <= 1'b1;
                                    state <= LOAD_GAME_READ_FST;
                                end
                                `HYPERVISOR_WRITE: begin
                                    //TODO: save game
                                end
                            endcase
                        end else begin
                            cpu_busy <= 1'b0;
                        end
                    end
                endcase
            end
            DELAY: begin
                if (delay_counter > 32'b0) begin
                    delay_counter <= delay_counter - 1'b1;
                end else begin
                    waitstate <= CONTINUE;
                end
            end
            WAIT_SPI: begin
                if (spi_state == IDLE) begin
                    flash_select <= flash_select_after_transfer;
                    waitstate <= CONTINUE;
                end
            end
        endcase
    end
endmodule
