`default_nettype none
`timescale 1ns/1ps
module gpu(
        input wire clock,
        input wire [31:0] vram_data,
        input wire [4:0] scroll_x_low,
        input wire [5:0] scroll_y_low,
        input wire [4:0] scroll_x_high,
        input wire [5:0] scroll_y_high,
        input wire [15:0] palette,
        output wire [8:0] vram_address_low,
        output wire [8:0] vram_address_high,
        output reg [1:0] vram_start,
        output wire in_vblank,
        output reg [3:0] red,
        output reg [3:0] green,
        output reg [3:0] blue,
        output reg hsync,
        output reg vsync);
    reg [9:0] x = 10'b0;
    reg [9:0] y = 10'b0;
    reg [3:0] x_micro = 4'b0;
    reg [3:0] y_micro = 4'b0;
    reg [16:0] pixel_buffer [1:0];
    reg [8:0] vram_address [1:0];
    wire [4:0] scroll_x [1:0];
    wire [5:0] scroll_y [1:0];
    wire [15:0] vram_data_split [1:0];
    wire [1:0] pixel = {pixel_buffer[1][16], pixel_buffer[0][16]};
    wire visible = x < 10'd640 && y < 10'd320;
    assign vram_address_low = vram_address[0];
    assign vram_address_high = vram_address[1];
    assign scroll_x[0] = scroll_x_low;
    assign scroll_x[1] = scroll_x_high;
    assign scroll_y[0] = scroll_y_low;
    assign scroll_y[1] = scroll_y_high;
    assign vram_data_split[0] = vram_data[15:0];
    assign vram_data_split[1] = vram_data[31:16];
    assign in_vblank = y >= 10'd480;
    always @(posedge clock) begin
        red   <= {4{visible && palette[pixel * 4'd4 + 4'd3]}};
        green <= {4{visible && palette[pixel * 4'd4 + 4'd2]}};
        blue  <= {4{visible && palette[pixel * 4'd4 + 4'd1]}};
        hsync <= x < 10'd656 || x >= 10'd752;
        vsync <= y < 10'd490 || y >= 10'd492;
        x <= x + 1'b1;
        x_micro <= x_micro + 1'b1;
        if (x_micro[2]) begin
            x_micro <= 4'b0;
            if (x == 10'd799) begin
                x <= 10'b0;
                y <= y + 1'b1;
                y_micro <= y_micro + 1'b1;
                if (y_micro[2]) begin
                    y_micro <= 4'b0;
                    if (y == 10'd524) begin
                        y <= 10'b0;
                    end
                end
            end
        end
    end
    generate
        genvar i;
        for (i = 0; i < 2; i = i + 1) begin
            initial begin
                vram_address[i] = 9'b0;
                vram_start[i] = 1'b0;
                pixel_buffer[i] = 17'b0;
            end
            always @(posedge clock) begin
                if (x_micro[2] && x != 10'd799) begin
                    pixel_buffer[i] <= {pixel_buffer[i][15:0], 1'b0};
                end
                if (visible) begin
                    if (pixel_buffer[i][14:0] == 15'b0) begin
                        case (x_micro)
                            4'h2: begin
                                vram_address[i][2:0] <= vram_address[i][2:0] + 1'b1;
                                vram_start[i] <= 1'b1;
                            end
                            4'h4: begin
                                pixel_buffer[i] <= {vram_data_split[i], 1'b1};
                                vram_start[i] <= 1'b0;
                            end
                        endcase
                    end
                end else begin
                    case (x + scroll_x[i][1:0] * 8'd20)
                        10'd797: begin
                            vram_start[i] <= y < 10'd320;
                            if (y_micro[2]) begin
                                vram_address[i] <= vram_address[i] + 4'h8;
                                if (y == 10'd524) begin
                                    vram_address[i] <= {scroll_y[i], scroll_x[i][4:2]};
                                    vram_start[i] <= 1'b1;
                                end
                            end
                        end
                        10'd799: begin
                            if (vram_start[i] == 1'b1) begin
                                pixel_buffer[i] <= {vram_data_split[i], 1'b1};
                                vram_start[i] <= 1'b0;
                            end
                        end
                    endcase
                end
            end
        end
    endgenerate
endmodule
