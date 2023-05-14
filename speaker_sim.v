`ifdef SIMULATED
    `default_nettype none
    `timescale 1ns/1ps
    module speaker_sim(
            input wire data);
        integer audio_file;
        initial begin
            audio_file = $fopen("/tmp/chip8-audio.raw", "wb"); 
        end
        always begin
            #22675
            $fwrite(audio_file, "%c", data ? 8'hff : 8'b0);
        end
    endmodule
`endif
