`ifdef SIMULATED
    `default_nettype none
    `timescale 1ns/1ps
    module display_sim(
            input wire clock,
            input wire [3:0] red,
            input wire [3:0] green,
            input wire [3:0] blue,
            input wire hsync,
            input wire vsync);
        reg [255:0] video_filename;
        integer video_file;
        reg [9:0] x = 10'b0;
        reg [9:0] y = 10'b0;
        integer frame = 0;
        wire visible = x < 10'd640 && y < 10'd480;
        initial begin
            video_file = $fopen("/tmp/chip8-video-00000000.raw", "wb"); 
            frame <= frame + 1;
        end
        always @(posedge clock) begin
            x <= x + 1'b1;
            if (x == 10'd799) begin
                x <= 10'b0;
                y <= y + 1'b1;
                if (y == 10'd524) begin
                    y <= 10'b0;
                end
            end
            if (visible) begin
                $fwrite(video_file, "%c%c%c", {2{blue}}, {2{green}}, {2{red}});
            end
        end
        always @(negedge hsync) begin
            x <= 10'd656;
        end
        always @(negedge vsync) begin
            y <= 10'd490;
            $fclose(video_file);
            $sformat(video_filename, "/tmp/chip8-video-%08x.raw", frame);
            video_file = $fopen(video_filename, "wb");
            frame <= frame + 1;
        end
    endmodule
`endif
