`default_nettype none
`timescale 1ns/1ps
module top (
`ifdef SIMULATED
`else
    input gpio_20,  //fast_clock
    input gpio_18,  //keypad_column[3]
    input gpio_11,  //keypad_column[2]
    input gpio_9,   //keypad_column[1]
    input gpio_6,   //keypad_column[0]
    input gpio_44,  //reset_user
    input spi_mosi,
    output gpio_12, //keypad_row[3]
    output gpio_21, //keypad_row[2]
    output gpio_13, //keypad_row[1]
    output gpio_19, //keypad_row[0]
    output gpio_31, //sound_out
    output gpio_23, //vga_red[3]
    output gpio_25, //vga_green[3]
    output gpio_26, //vga_blue[3]
    output gpio_27, //vga_hsync
    output gpio_32, //vga_vsync
    output led_red,
    output led_green,
    output led_blue,
    output spi_sck,
    output spi_ssn,
    output spi_miso
`endif
    );
    wire [15:0] cpu_mm_address;
    wire [7:0] cpu_mm_data_out;
    wire cpu_mm_direction;
    wire [7:0] cpu_mm_data_in;
    wire [31:0] cpu_vram_data_in;
    wire cpu_apu_enable;
    wire [31:0] cpu_vram_data_out;
    wire [31:0] gpu_vram_data;
    wire [8:0] cpu_vram_address;
    wire [8:0] gpu_vram_address [1:0];
    wire [1:0] cpu_vram_direction;
    wire [1:0] cpu_vram_start;
    wire [1:0] gpu_vram_start;
    wire apu_load_pattern;
    wire [127:0] apu_pattern_in;
    wire sound_out;
    wire reset_user;
    wire [3:0] keypad_column;
    wire [3:0] keypad_row;
    wire [7:0] cpu_bcd_out;
    wire cpu_bcd_start;
    wire [9:0] cpu_bcd_in;
    wire in_vblank;
    wire frame_start;
    wire [3:0] vga_red;
    wire [3:0] vga_green;
    wire [3:0] vga_blue;
    wire vga_hsync;
    wire vga_vsync;
    reg [23:0] clock_counter = 24'b0;
    wire clock = clock_counter[1];
    wire pll_locked;
    wire [4:0] scroll_x_back_low;
    wire [5:0] scroll_y_back_low;
    wire [4:0] scroll_x_back_high;
    wire [5:0] scroll_y_back_high;
    wire [4:0] scroll_x_front_low;
    wire [5:0] scroll_y_front_low;
    wire [4:0] scroll_x_front_high;
    wire [5:0] scroll_y_front_high;
    wire reset;
    wire [7:0] hypervisor_bram_ipl_data;
    wire [15:0] hypervisor_mm_address;
    wire [7:0] hypervisor_mm_data_out;
    wire hypervisor_mm_control;
    wire [11:0] hypervisor_bram_ipl_address;
    wire hypervisor_bram_ipl_start;
    wire [15:0] apu_sub_frequency;
    wire [7:0] cpu_pitch_out;
    wire cpu_pitch_start;
    wire [15:0] keypad;
    wire [15:0] released_keys;
    wire released_keys_clear;
    //wire [15:0] user_signals;
    wire hypervisor_flash_clock;
    wire hypervisor_flash_select;
    wire hypervisor_flash_data_in;
    wire hypervisor_flash_data_out;
    wire [3:0] cpu_hypervisor_opcode;
    wire [7:0] cpu_hypervisor_game_index;
    wire [7:0] cpu_hypervisor_previous_page;
    wire [7:0] cpu_hypervisor_last_page;
    wire cpu_hypervisor_parse_header;
    wire cpu_hypervisor_execute;
    wire cpu_hypervisor_busy;
    /*
    wire [7:0] ps2_scancode_out;
    wire ps2_scancode_start;
    wire ps2_clock;
    wire ps2_data;
    wire [15:0] ps2_action_in;
    */
    wire [63:0] cpu_quirks;
    wire [63:0] keymap;
    wire [15:0] gpu_palette;
    wire [15:0] cpu_instructions_per_frame;
    wire hypervisor_debug_out;
    wire cpu_debug_out;
    wire alternate_debug_out = hypervisor_flash_select;
    `ifdef SIMULATED
        initial begin
            `ifdef DUMPVARS
                $dumpfile("/tmp/chip8.vcd");
                $dumpvars;
            `endif
        end
        reg [63:0] frame_counter = 64'b0;
        always @(posedge frame_start) begin
            frame_counter <= frame_counter + 1'b1;
        end
        reg fast_clock = 1'b0;
        reg [63:0] frame = 64'b0;
        assign reset_user = 1'b1;
        reg bypass_flash = 1'b0;
        /*
        wire [15:0] keypad_internal = {{0{1'b0}}, {16{clock_counter[20]}}, {0{1'b1}}};
        generate
            genvar i;
            for (i = 0; i < 4; i = i + 1) begin
                wire [1:0] row = $clog2(~keypad_row);
                assign keypad_column[i] = keypad_internal[{row, i[1:0]}];
            end
        endgenerate
        //assign keypad = {{1{1'b0}}, {8{clock_counter[23]}}, {7{1'b1}}};
        */
        flash_sim my_flash_sim(
                .clock(hypervisor_flash_clock),
                .select(hypervisor_flash_select),
                .data_in(hypervisor_flash_data_out),
                .data_out(hypervisor_flash_data_in));
        speaker_sim my_speaker_sim(
                .data(sound_out));
        display_sim my_display_sim(
                .clock(fast_clock),
                .red(vga_red),
                .green(vga_green),
                .blue(vga_blue),
                .hsync(vga_hsync),
                .vsync(vga_vsync));
        keypad_sim my_keypad_sim(
                .keypad_row(keypad_row),
                .keypad_column(keypad_column));
    `else
        wire fast_clock;
        wire bypass_flash = 1'b0; //TODO: assign to GPIO
        assign keypad_column = {gpio_18, gpio_11, gpio_9, gpio_6};
        assign reset_user = gpio_44;
        assign {gpio_12, gpio_21, gpio_13, gpio_19}  = keypad_row;
        assign gpio_31 = sound_out;
        assign
                {gpio_23, gpio_25, gpio_26, gpio_27, gpio_32}
              = {vga_red[3], vga_green[3], vga_blue[3], vga_hsync, vga_vsync};
        assign {spi_sck, spi_ssn, spi_miso} = {
                hypervisor_flash_clock,
                hypervisor_flash_select,
                hypervisor_flash_data_out};
        assign hypervisor_flash_data_in = spi_mosi;
        SB_RGBA_DRV #(
                .CURRENT_MODE("0b1"),
                .RGB0_CURRENT("0b000001"),
                .RGB1_CURRENT("0b000001"), 
                .RGB2_CURRENT("0b000001")) led_debug_driver(
                .RGB0(led_green),
                .RGB1(led_blue),
                .RGB2(led_red),
                .RGB0PWM(hypervisor_debug_out),
                .RGB1PWM(cpu_debug_out),
                .RGB2PWM(alternate_debug_out),
                .RGBLEDEN(1'b1),
                .CURREN(1'b1));
        //internal oscillator code (do not use VGA when enabled):
        /*
            wire clock_12mhz;
            SB_HFOSC #(
                    .CLKHF_DIV("0b10")) hfosc(
                    .CLKHFEN(1'b1),
                    .CLKHF(clock_12mhz),
                    .CLKHFPU(1'b1));
            pll my_pll(
                    .clock_in(clock_12mhz),
                    .clock_out(fast_clock),
                    .locked(pll_locked));
        */
        pll my_pll(
                .clock_in(gpio_20),
                .clock_out(fast_clock),
                .locked(pll_locked));
    `endif
    always @(posedge fast_clock) begin
        clock_counter <= clock_counter + 1'b1;
    end

    bram_ipl my_bram_ipl(
            .clock(clock),
            .address(hypervisor_bram_ipl_address),
            .start(hypervisor_bram_ipl_start),
            .data(hypervisor_bram_ipl_data));
    hypervisor my_hypervisor(
            .clock(clock),
            .reset_user(reset_user),
            .bypass_flash(bypass_flash),
            .bram_ipl_data_in(hypervisor_bram_ipl_data),
            .flash_data_in(hypervisor_flash_data_in),
            .cpu_opcode(cpu_hypervisor_opcode),
            .cpu_game_index(cpu_hypervisor_game_index),
            .cpu_previous_page(cpu_hypervisor_previous_page),
            .cpu_last_page(cpu_hypervisor_last_page),
            .cpu_parse_header(cpu_hypervisor_parse_header),
            .cpu_execute(cpu_hypervisor_execute),
            .reset(reset),
            .mm_address(hypervisor_mm_address),
            .mm_data_out(hypervisor_mm_data_out),
            .mm_control(hypervisor_mm_control),
            .bram_ipl_address(hypervisor_bram_ipl_address),
            .bram_ipl_start(hypervisor_bram_ipl_start),
            .flash_clock(hypervisor_flash_clock),
            .flash_select(hypervisor_flash_select),
            .flash_data_out(hypervisor_flash_data_out),
            .cpu_busy(cpu_hypervisor_busy),
            .quirks(cpu_quirks),
            .keymap(keymap),
            .palette(gpu_palette),
            .instructions_per_frame(cpu_instructions_per_frame),
            .debug_out(hypervisor_debug_out));
    cpu_memory my_cpu_memory(
            .clock(clock),
            .hypervisor_control(hypervisor_mm_control),
            .cpu_address(cpu_mm_address),
            .hypervisor_address(hypervisor_mm_address),
            .cpu_data_in(cpu_mm_data_out),
            .hypervisor_data_in(hypervisor_mm_data_out),
            .cpu_direction(cpu_mm_direction),
            .data_out(cpu_mm_data_in));
    bcd_lut my_bcd_lut(
            .clock(clock),
            .address(cpu_bcd_out),
            .start(cpu_bcd_start),
            .data(cpu_bcd_in));
    pitch_lut my_pitch_lut(
            .clock(clock),
            .address(cpu_pitch_out),
            .start(cpu_pitch_start),
            .data(apu_sub_frequency));
    vram my_vram(
            .clock(fast_clock),
            .reset(reset),
            .cpu_data_in(cpu_vram_data_out),
            .cpu_address(cpu_vram_address),
            .cpu_direction(cpu_vram_direction),
            .cpu_start(cpu_vram_start),
            .cpu_scroll_x_low(scroll_x_back_low),
            .cpu_scroll_y_low(scroll_y_back_low),
            .cpu_scroll_x_high(scroll_x_back_high),
            .cpu_scroll_y_high(scroll_y_back_high),
            .gpu_address_low(gpu_vram_address[0]),
            .gpu_address_high(gpu_vram_address[1]),
            .gpu_start(gpu_vram_start),
            .in_vblank(in_vblank),
            .cpu_data_out(cpu_vram_data_in),
            .gpu_data_out(gpu_vram_data),
            .gpu_scroll_x_low(scroll_x_front_low),
            .gpu_scroll_y_low(scroll_y_front_low),
            .gpu_scroll_x_high(scroll_x_front_high),
            .gpu_scroll_y_high(scroll_y_front_high),
            .frame_start(frame_start));
    keypad my_keypad(
            .clock(clock),
            .reset(reset),
            .main_frequency(32'd6281250),
            .poll_frequency(24'd100),
            .released_keys_clear(released_keys_clear),
            .keymap(keymap),
            .keypad_column(keypad_column),
            .keypad_row(keypad_row),
            .keypad_out(keypad),
            .released_keys_out(released_keys));
    cpu my_cpu(
            .clock(clock),
            .reset(reset),
            .instructions_per_frame(cpu_instructions_per_frame),
            .mm_data_in(cpu_mm_data_in),
            .vram_data_in(cpu_vram_data_in),
            .bcd_in(cpu_bcd_in),
            .sound_enable(cpu_apu_enable),
            .sound_load_pattern(apu_load_pattern),
            .sound_pattern_out(apu_pattern_in),
            .pitch_out(cpu_pitch_out),
            .pitch_start(cpu_pitch_start),
            .keypad(keypad),
            .released_keys(released_keys),
            .in_vblank(in_vblank),
            .quirks(cpu_quirks),
            .hypervisor_busy(cpu_hypervisor_busy),
            .mm_address(cpu_mm_address),
            .mm_data_out(cpu_mm_data_out),
            .mm_direction(cpu_mm_direction),
            .vram_data_out(cpu_vram_data_out),
            .vram_address(cpu_vram_address),
            .vram_direction(cpu_vram_direction),
            .vram_start(cpu_vram_start),
            .bcd_out(cpu_bcd_out),
            .bcd_start(cpu_bcd_start),
            .scroll_x_low(scroll_x_back_low),
            .scroll_y_low(scroll_y_back_low),
            .scroll_x_high(scroll_x_back_high),
            .scroll_y_high(scroll_y_back_high),
            .hypervisor_opcode(cpu_hypervisor_opcode),
            .hypervisor_game_index(cpu_hypervisor_game_index),
            .hypervisor_previous_page(cpu_hypervisor_previous_page),
            .hypervisor_last_page(cpu_hypervisor_last_page),
            .hypervisor_parse_header(cpu_hypervisor_parse_header),
            .hypervisor_execute(cpu_hypervisor_execute),
            .released_keys_clear(released_keys_clear),
            .debug_out(cpu_debug_out));
    gpu my_gpu(
            .clock(fast_clock),
            .vram_data(gpu_vram_data),
            .scroll_x_low(scroll_x_front_low),
            .scroll_y_low(scroll_y_front_low),
            .scroll_x_high(scroll_x_front_high),
            .scroll_y_high(scroll_y_front_high),
            .palette(gpu_palette),
            .vram_address_low(gpu_vram_address[0]),
            .vram_address_high(gpu_vram_address[1]),
            .vram_start(gpu_vram_start),
            .in_vblank(in_vblank),
            .red(vga_red),
            .green(vga_green),
            .blue(vga_blue),
            .hsync(vga_hsync),
            .vsync(vga_vsync));
    apu my_apu(
            .clock(clock),
            .reset(reset),
            .enable(cpu_apu_enable),
            .main_frequency(32'd6281250),
            .sub_frequency(apu_sub_frequency),
            .pattern_in(apu_pattern_in),
            .load_pattern(apu_load_pattern),
            .sound_out(sound_out));
    /*
    ps2_controller my_ps2_controller(
            .clock(clock),
            .reset(reset),
            .ps2_clock(ps2_clock),
            .data(ps2_data),
            .action(ps2_action_in),
            .scancode(ps2_scancode_out),
            .scancode_start(ps2_scancode_start),
            .keypad(keypad),
            .signals(user_signals));
    keymap my_keymap(
            .clock(clock),
            .address(ps2_scancode_out),
            .start(ps2_scancode_start),
            .data(ps2_action_in));
    */
    `ifdef SIMULATED
        always begin
            #20
            fast_clock = 0;
            #20
            fast_clock = 1;
        end
    `endif
endmodule
