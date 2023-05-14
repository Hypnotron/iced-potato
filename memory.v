`default_nettype none
`timescale 1ns/1ps
module cpu_memory(
        input wire clock,
        input wire hypervisor_control,
        input wire [15:0] cpu_address,
        input wire [15:0] hypervisor_address,
        input wire [7:0] cpu_data_in,
        input wire [7:0] hypervisor_data_in,
        input wire cpu_direction, //0: read, 1: write
        output wire [7:0] data_out);
    wire [15:0] address = 
            hypervisor_control
          ? hypervisor_address
          : cpu_address;
    wire [7:0] data_in =
            hypervisor_control
          ? hypervisor_data_in 
          : cpu_data_in;
    wire direction =
            hypervisor_control
          ? 1'b1
          : cpu_direction;
    reg [15:0] latched_address;
    always @(posedge clock) begin
        latched_address <= address;
    end
    wire [15:0] raw_data_out0;
    wire [15:0] raw_data_out1;
    wire [15:0] raw_data_out = 
            latched_address[15]
          ? raw_data_out1
          : raw_data_out0;
    assign data_out =
            latched_address[0]
          ? raw_data_out[15:8]
          : raw_data_out[7:0];
    wire [15:0] raw_data_in = address[0] ? {data_in, 8'b0} : {8'b0, data_in};
    `ifdef SIMULATED
        reg [15:0] spram0 [16383:0];
        reg [15:0] spram1 [16383:0];
        reg [15:0] data_out0;
        reg [15:0] data_out1;
        assign raw_data_out0 = data_out0;
        assign raw_data_out1 = data_out1;
        wire [3:0] maskwren = {{2{address[0]}}, {2{~address[0]}}};
        wire [15:0] wem = {
            {4{maskwren[3]}},
            {4{maskwren[2]}},
            {4{maskwren[1]}},
            {4{maskwren[0]}}};
        always @(posedge clock) begin
            if (direction) begin
                if (address[15]) begin
                    spram1[address[14:1]] <= 
                            spram1[address[14:1]]
                          & ~wem
                          | (raw_data_in & wem);
                end else begin
                    spram0[address[14:1]] <= 
                            spram0[address[14:1]]
                          & ~wem
                          | (raw_data_in & wem);
                end
            end else begin
                if (address[15]) begin
                    data_out1 <= spram1[address[14:1]];
                end else begin
                    data_out0 <= spram0[address[14:1]];
                end
            end
        end
        initial begin
            $readmemh("/tmp/cpu_mm_0.txt", spram0, 16'h0, 16'h3fff);
            $readmemh("/tmp/cpu_mm_1.txt", spram1, 16'h0, 16'h3fff);
        end
        generate
            genvar i;
            for (i = 0; i < 2048; i = i + 1) begin: dump_spram
                initial begin
                    `ifdef DUMPVARS
                        $dumpfile("/tmp/chip8.vcd");
                        $dumpvars(0, spram0[i]);
                    `endif
                    //$dumpvars(0, spram1[i]);
                end
            end
        endgenerate
    `else
        SB_SPRAM256KA spram0(
                .DATAIN(raw_data_in),
                .ADDRESS(address[14:1]),
                .MASKWREN({address[0], address[0], ~address[0], ~address[0]}),
                .WREN(direction),
                .CHIPSELECT(1'b1),
                .CLOCK(clock),
                .STANDBY(address[15]),
                .SLEEP(1'b0),
                .POWEROFF(1'b1),
                .DATAOUT(raw_data_out0));
        SB_SPRAM256KA spram1(
                .DATAIN(raw_data_in),
                .ADDRESS(address[14:1]),
                .MASKWREN({address[0], address[0], ~address[0], ~address[0]}),
                .WREN(direction),
                .CHIPSELECT(1'b1),
                .CLOCK(clock),
                .STANDBY(~address[15]),
                .SLEEP(1'b0),
                .POWEROFF(1'b1),
                .DATAOUT(raw_data_out1));
    `endif
endmodule
module vram(
        input wire clock,
        input wire reset,
        input wire [31:0] cpu_data_in,
        input wire [8:0] cpu_address,
        input wire [1:0] cpu_direction,
        input wire [1:0] cpu_start,
        input wire [4:0] cpu_scroll_x_low,
        input wire [5:0] cpu_scroll_y_low,
        input wire [4:0] cpu_scroll_x_high,
        input wire [5:0] cpu_scroll_y_high,
        input wire [8:0] gpu_address_low,
        input wire [8:0] gpu_address_high,
        input wire [1:0] gpu_start,
        input wire in_vblank,
        output wire [31:0] cpu_data_out,
        output wire [31:0] gpu_data_out,
        output reg [4:0] gpu_scroll_x_low,
        output reg [5:0] gpu_scroll_y_low,
        output reg [4:0] gpu_scroll_x_high,
        output reg [5:0] gpu_scroll_y_high,
        output wire frame_start);
    reg [8:0] flip_source_address;
    reg [8:0] flip_destination_address;
    reg [31:0] flip_data;
    reg flip_start;
    reg flip_write_enable;
    reg flip_read_enable;
    localparam START        = 4'h0;
    localparam READ         = 4'h1;
    localparam WRITE        = 4'h2;
    localparam INCREMENT    = 4'h3;
    localparam DONE         = 4'h4;
    reg [2:0] flip_state;
    localparam DELAY        = 1'h0;
    localparam CONTINUE     = 1'h1;
    reg flip_waitstate;
    wire [8:0] gpu_address [1:0];
    assign gpu_address[0] = gpu_address_low;
    assign gpu_address[1] = gpu_address_high;
    wire [15:0] raw_data_out_front [3:0];
    wire [15:0] raw_data_out_back [3:0];
    wire flipping = in_vblank && flip_state != DONE;
    wire [8:0] address_back = 
            flipping
          ? flip_source_address 
          : cpu_address;
    wire [1:0] start_back;
    wire [15:0] raw_data_in [1:0];
    reg [8:0] latched_address_back;
    reg [8:0] latched_gpu_address [1:0];
    always @(posedge clock) begin
        latched_address_back <= address_back;
        //TODO: generate expression
        latched_gpu_address[0] <= gpu_address[0];
        latched_gpu_address[1] <= gpu_address[1];
    end
    generate
        genvar i;
        genvar j;
        for (i = 0; i < 2; i = i + 1) begin
            assign start_back[i] = 
                    flipping
                  ? flip_read_enable
                  : cpu_start[i] && !cpu_direction[i];
            assign raw_data_in[i] = 
                    flipping
                  ? flip_data[i * 16 + 15 : i * 16]
                  : cpu_data_in[i * 16 + 15 : i * 16];
            assign cpu_data_out[i * 16 + 15 : i * 16] = 
                    raw_data_out_back[{i[0], latched_address_back[8]}];
            assign gpu_data_out[i * 16 + 15 : i * 16] = 
                    raw_data_out_front[{i[0], latched_gpu_address[i[0]][8]}];
        end
    endgenerate
    assign frame_start = flip_state == DONE;
    `ifdef SIMULATED 
        generate
            for (i = 0; i < 2; i = i + 1) begin: bramsi
                for (j = 0; j < 2; j = j + 1) begin: bramsj
                    reg [15:0] ram_front [255:0];
                    reg [15:0] ram_back [255:0];
                    reg [15:0] rdata_front;
                    reg [15:0] rdata_back;
                    assign raw_data_out_front[{j[0], i[0]}] = rdata_front;
                    assign raw_data_out_back[{j[0], i[0]}] = rdata_back;
                    always @(posedge clock) begin
                        if (
                                flip_write_enable
                             && flip_destination_address[8] == i[0]) begin
                            ram_front[flip_destination_address[7:0]] <=
                                    raw_data_in[j[0]];
                        end
                        if (
                                !flipping
                             && cpu_direction[j[0]]
                             && address_back[8] == i[0]) begin
                            ram_back[address_back[7:0]] <= raw_data_in[j[0]];
                        end
                        if (gpu_start[j[0]] && gpu_address[j[0]][8] == i[0]) begin
                            rdata_front <= ram_front[gpu_address[j[0]][7:0]];
                        end
                        if (start_back[j[0]] && address_back[8] == i[0]) begin
                            rdata_back <= ram_back[address_back[7:0]];
                        end
                    end
                end
                for (j = 0; j < 256; j = j + 1) begin
                    initial begin
                        `ifdef DUMPVARS
                            $dumpfile("/tmp/chip8.vcd");
                            $dumpvars(0, ram_front[j]);
                            $dumpvars(0, ram_back[j]);
                        `endif
                    end
                end
            end
        endgenerate
        initial begin
            $readmemh("/tmp/vram_0.txt", bramsi[0].bramsj[0].ram_front, 8'h0, 8'hff);
            $readmemh("/tmp/vram_1.txt", bramsi[1].bramsj[0].ram_front, 8'h0, 8'hff);
            $readmemh("/tmp/vram_2.txt", bramsi[0].bramsj[1].ram_front, 8'h0, 8'hff);
            $readmemh("/tmp/vram_3.txt", bramsi[1].bramsj[1].ram_front, 8'h0, 8'hff);
            $readmemh("/tmp/vram_4.txt", bramsi[0].bramsj[0].ram_back, 8'h0, 8'hff);
            $readmemh("/tmp/vram_5.txt", bramsi[1].bramsj[0].ram_back, 8'h0, 8'hff);
            $readmemh("/tmp/vram_6.txt", bramsi[0].bramsj[1].ram_back, 8'h0, 8'hff);
            $readmemh("/tmp/vram_7.txt", bramsi[1].bramsj[1].ram_back, 8'h0, 8'hff);
        end
    `else
        generate
            for (i = 0; i < 2; i = i + 1) begin: brams 
                for (j = 0; j < 2; j = j + 1) begin
                    SB_RAM40_4K #(
                            .INIT_0(256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
                            .INIT_1(256'b0),
                            .INIT_2(256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
                            .INIT_3(256'b0),
                            .INIT_4(256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
                            .INIT_5(256'b0),
                            .INIT_6(256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
                            .INIT_7(256'b0),
                            .INIT_8(256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
                            .INIT_9(256'b0),
                            .INIT_A(256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
                            .INIT_B(256'b0),
                            .INIT_C(256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
                            .INIT_D(256'b0),
                            .INIT_E(256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
                            .INIT_F(256'b0),
                            .WRITE_MODE(32'b0), //0: 256x16
                            .READ_MODE(32'b0)) bram_front (
                            .RDATA(raw_data_out_front[{j[0], i[0]}]),
                            .WDATA(raw_data_in[j[0]]),
                            .RADDR({3'b0, gpu_address[j[0]][7:0]}),
                            .WADDR({3'b0, flip_destination_address[7:0]}),
                            .MASK(16'b0),
                            .RCLKE(gpu_start[j[0]] && gpu_address[j[0]][8] == i[0]),
                            .RCLK(clock),
                            .RE(gpu_start[j[0]] && gpu_address[j[0]][8] == i[0]),
                            .WCLKE(
                                    flip_write_enable
                                 && flip_destination_address[8] == i[0]),
                            .WCLK(clock),
                            .WE(
                                    flip_write_enable
                                 && flip_destination_address[8] == i[0]));
                    SB_RAM40_4K #(
                            .INIT_0(256'hff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00),
                            .INIT_1(256'b0),
                            .INIT_2(256'hff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00),
                            .INIT_3(256'b0),
                            .INIT_4(256'hff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00),
                            .INIT_5(256'b0),
                            .INIT_6(256'hff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00),
                            .INIT_7(256'b0),
                            .INIT_8(256'hff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00),
                            .INIT_9(256'b0),
                            .INIT_A(256'hff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00),
                            .INIT_B(256'b0),
                            .INIT_C(256'hff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00),
                            .INIT_D(256'b0),
                            .INIT_E(256'hff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00),
                            .INIT_F(256'b0),
                            .WRITE_MODE(32'b0), //0: 256x16
                            .READ_MODE(32'b0)) bram_back (
                            .RDATA(raw_data_out_back[{j[0], i[0]}]),
                            .WDATA(raw_data_in[j[0]]),
                            .RADDR({3'b0, address_back[7:0]}),
                            .WADDR({3'b0, address_back[7:0]}),
                            .MASK(16'b0),
                            .RCLKE(start_back[j[0]] && address_back[8] == i[0]),
                            .RCLK(clock),
                            .RE(start_back[j[0]] && address_back[8] == i[0]),
                            .WCLKE(
                                    !flipping
                                 && cpu_direction[j[0]] && address_back[8] == i[0]),
                            .WCLK(clock),
                            .WE(
                                    !flipping
                                 && cpu_direction[j[0]] && address_back[8] == i[0]));
                end
            end
        endgenerate
    `endif
    always @(posedge clock) begin
        if (!reset) begin
            flip_data <= 32'b0;
            flip_source_address <= 9'b0;
            flip_destination_address <= 9'b0;
            flip_write_enable <= 1'b0;
            flip_read_enable <= 1'b0;
            flip_state <= DONE;
            flip_waitstate <= CONTINUE;
        end else begin
            if (in_vblank) begin
                case (flip_waitstate)
                    DELAY: begin
                        flip_waitstate <= CONTINUE;
                    end
                endcase
                if (flip_waitstate == CONTINUE) begin
                    case (flip_state)
                        START: begin
                            flip_source_address <= 9'b0;
                            flip_destination_address <= 9'h1ff;
                            flip_write_enable <= 1'b0;
                            flip_read_enable <= 1'b1;
                            flip_waitstate <= DELAY;
                            flip_state <= READ;
                        end
                        READ: begin
                            flip_data <= {
                                    raw_data_out_back[{1'b1, flip_source_address[8]}],
                                    raw_data_out_back[{1'b0, flip_source_address[8]}]};
                            flip_source_address <= flip_source_address + 1'b1;
                            flip_destination_address <= flip_destination_address + 1'b1;
                            flip_write_enable <= 1'b1;
                            flip_state <= WRITE;
                        end
                        WRITE: begin
                            flip_write_enable <= 1'b0;
                            flip_state <= READ;
                            if (flip_destination_address == 9'h1ff) begin
                                flip_waitstate <= DELAY;
                                flip_state <= DONE;
                                flip_read_enable <= 1'b0;
                                gpu_scroll_x_low <= cpu_scroll_x_low;
                                gpu_scroll_y_low <= cpu_scroll_y_low;
                                gpu_scroll_x_high <= cpu_scroll_x_high;
                                gpu_scroll_y_high <= cpu_scroll_y_high;
                                `ifdef SIMULATED
                                    $writememh("/tmp/vram_0.txt", bramsi[0].bramsj[0].ram_front, 8'h0, 8'hff);
                                    $writememh("/tmp/vram_1.txt", bramsi[1].bramsj[0].ram_front, 8'h0, 8'hff);
                                    $writememh("/tmp/vram_2.txt", bramsi[0].bramsj[1].ram_front, 8'h0, 8'hff);
                                    $writememh("/tmp/vram_3.txt", bramsi[1].bramsj[1].ram_front, 8'h0, 8'hff);
                                `endif
                            end
                        end
                        DONE: begin
                        end
                    endcase
                end
            end else begin
                flip_state <= START;
            end
        end
    end
endmodule
module bcd_lut(
        input wire clock,
        input wire [7:0] address,
        input wire start,
        output wire [9:0] data);
        wire [15:0] raw_data;
        assign data = raw_data[9:0];
        `ifdef SIMULATED
            reg [15:0] bram [255:0];
            reg [15:0] rdata;
            assign raw_data = rdata;
            generate
                genvar i;
                for (i = 0; i < 256; i = i + 1) begin
                    initial begin
                        bram[i][9:8] = i / 100;
                        bram[i][7:4] = (i / 10) % 10;
                        bram[i][3:0] = i % 10;
                    end
                end
            endgenerate
            always @(posedge clock) begin
                if (start) begin
                    rdata <= bram[address];
                end
            end
        `else
            SB_RAM40_4K #(
                    .INIT_0(256'h0015001400130012001100100009000800070006000500040003000200010000),
                    .INIT_1(256'h0031003000290028002700260025002400230022002100200019001800170016),
                    .INIT_2(256'h0047004600450044004300420041004000390038003700360035003400330032),
                    .INIT_3(256'h0063006200610060005900580057005600550054005300520051005000490048),
                    .INIT_4(256'h0079007800770076007500740073007200710070006900680067006600650064),
                    .INIT_5(256'h0095009400930092009100900089008800870086008500840083008200810080),
                    .INIT_6(256'h0111011001090108010701060105010401030102010101000099009800970096),
                    .INIT_7(256'h0127012601250124012301220121012001190118011701160115011401130112),
                    .INIT_8(256'h0143014201410140013901380137013601350134013301320131013001290128),
                    .INIT_9(256'h0159015801570156015501540153015201510150014901480147014601450144),
                    .INIT_A(256'h0175017401730172017101700169016801670166016501640163016201610160),
                    .INIT_B(256'h0191019001890188018701860185018401830182018101800179017801770176),
                    .INIT_C(256'h0207020602050204020302020201020001990198019701960195019401930192),
                    .INIT_D(256'h0223022202210220021902180217021602150214021302120211021002090208),
                    .INIT_E(256'h0239023802370236023502340233023202310230022902280227022602250224),
                    .INIT_F(256'h0255025402530252025102500249024802470246024502440243024202410240),
                    .WRITE_MODE(32'b0), //0: 256x16
                    .READ_MODE(32'b0)) bram (
                    .RDATA(raw_data),
                    .WDATA(16'b0),
                    .RADDR({3'b0, address}),
                    .WADDR(11'b0),
                    .MASK(16'hffff),
                    .RCLKE(start),
                    .RCLK(clock),
                    .RE(start),
                    .WCLKE(1'b0),
                    .WCLK(1'b0),
                    .WE(1'b0));
        `endif
endmodule
module bram_ipl(
        input wire clock,
        input wire [11:0] address,
        input wire start,
        output wire [7:0] data);
        reg [11:0] latched_address;
        always @(posedge clock) begin
            latched_address <= address;
        end
        wire [15:0] raw_data [7:0];
        assign data = 
                latched_address[0]
              ? raw_data[latched_address[11:9]][15:8]
              : raw_data[latched_address[11:9]][7:0];
        `ifdef SIMULATED
            generate
                genvar i;
                for (i = 0; i < 8; i = i + 1) begin: brams 
                    reg [15:0] bram [255:0];
                    reg [15:0] rdata;
                    assign raw_data[i] = rdata;
                    always @(posedge clock) begin
                        if (start && i[2:0] == address[11:9]) begin
                            rdata <= bram[address[8:1]];
                        end
                    end
                end
                initial begin
                    $readmemh("/tmp/bram_ipl_0.txt", brams[0].bram, 8'h0, 8'hff);
                    $readmemh("/tmp/bram_ipl_1.txt", brams[1].bram, 8'h0, 8'hff);
                    $readmemh("/tmp/bram_ipl_2.txt", brams[2].bram, 8'h0, 8'hff);
                    $readmemh("/tmp/bram_ipl_3.txt", brams[3].bram, 8'h0, 8'hff);
                    $readmemh("/tmp/bram_ipl_4.txt", brams[4].bram, 8'h0, 8'hff);
                    $readmemh("/tmp/bram_ipl_5.txt", brams[5].bram, 8'h0, 8'hff);
                    $readmemh("/tmp/bram_ipl_6.txt", brams[6].bram, 8'h0, 8'hff);
                    $readmemh("/tmp/bram_ipl_7.txt", brams[7].bram, 8'h0, 8'hff);
                end
            endgenerate
        `endif
endmodule
module pitch_lut(
        input wire clock,
        input wire [7:0] address,
        input wire start,
        output wire [15:0] data);
        `ifdef SIMULATED
            reg [15:0] bram [255:0];
            reg [15:0] rdata;
            assign data = rdata;
            generate
                genvar i;
                for (i = 0; i < 256; i = i + 1) begin
                    initial begin
                        bram[i] = 4000 * $pow(2, (i - 64) / 48.0);
                    end
                end
            endgenerate
            always @(posedge clock) begin
                if (start) begin
                    rdata <= bram[address];
                end
            end
        `else
            SB_RAM40_4K #(
                    .INIT_0(256'h07b30797077b075f0744072a070f06f506dc06c306aa069106790661064a0633),
                    .INIT_1(256'h09b30990096d094a0928090608e508c408a40885086508460828080a07ed07d0),
                    .INIT_2(256'h0c390c0c0be00bb40b890b5f0b350b0c0ae30abb0a940a6d0a470a2109fc09d7),
                    .INIT_3(256'h0f660f2e0ef60ebf0e890e540e1f0deb0db80d860d540d230cf30cc30c940c66),
                    .INIT_4(256'h1367132012da12941250120d11cb11891149110a10cb108d105110150fda0fa0),
                    .INIT_5(256'h1872181817c01769171316be166b161815c71577152914db148e144313f813af),
                    .INIT_6(256'h1ecd1e5c1dec1d7e1d121ca81c3e1bd71b711b0c1aa91a4719e61987192918cd),
                    .INIT_7(256'h26ce264025b4252924a1241a23962313229222142196211b20a2202a1fb41f40),
                    .INIT_8(256'h30e530312f802ed22e262d7d2cd62c312b8f2aef2a5229b6291d288627f1275f),
                    .INIT_9(256'h3d9a3cb83bd93afd3a253950387d37ae36e236183552348e33cd330f3253319b),
                    .INIT_A(256'h4d9d4c804b684a5349424835472c462745254428432d4237414440543f683e80),
                    .INIT_B(256'h61ca60635f015da45c4d5afa59ac5863571f55df54a4536d523b510d4fe34ebe),
                    .INIT_C(256'h7b35797177b375fb744a72a070fb6f5c6dc46c316aa4691c679a661e64a76336),
                    .INIT_D(256'h9b3b990196d094a69285906b8e598c4e8a4b8850865b846e828880a97ed17d00),
                    .INIT_E(256'hc394c0c6be03bb49b89ab5f4b359b0c6ae3eabbea948a6daa476a21a9fc79d7d),
                    .INIT_F(256'hf66af2e2ef66ebf7e895e540e1f6deb9db88d862d548d239cf35cc3dc94fc66c),
                    .WRITE_MODE(32'b0), //0: 256x16
                    .READ_MODE(32'b0)) bram (
                    .RDATA(data),
                    .WDATA(16'b0),
                    .RADDR({3'b0, address}),
                    .WADDR(11'b0),
                    .MASK(16'hffff),
                    .RCLKE(start),
                    .RCLK(clock),
                    .RE(start),
                    .WCLKE(1'b0),
                    .WCLK(1'b0),
                    .WE(1'b0));
        `endif
endmodule
module keymap(
        input wire clock,
        input wire [7:0] address,
        input wire start,
        output wire [15:0] data);
        `ifdef SIMULATED
            reg [15:0] bram [255:0];
            reg [15:0] rdata;
            assign data = rdata;
            //TODO: init
            always @(posedge clock) begin
                if (start) begin
                    rdata <= bram[address];
                end
            end
        `else
            SB_RAM40_4K #(
                    //TODO: init
                    .WRITE_MODE(32'b0), //0: 256x16
                    .READ_MODE(32'b0)) bram (
                    .RDATA(data),
                    .WDATA(16'b0),
                    .RADDR({3'b0, address}),
                    .WADDR(11'b0),
                    .MASK(16'hffff),
                    .RCLKE(start),
                    .RCLK(clock),
                    .RE(start),
                    .WCLKE(1'b0),
                    .WCLK(1'b0),
                    .WE(1'b0));
        `endif
endmodule
