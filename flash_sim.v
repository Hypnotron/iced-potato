`ifdef SIMULATED
    `default_nettype none
    `timescale 1ns/1ps
    module flash_sim(
            input wire clock,
            input wire select,
            input wire data_in,
            output reg data_out);
        reg [7:0] memory [4194304:0];
        initial begin
            $readmemh("/tmp/flash.txt", memory, 24'h0, 24'h3fffff);
        end
        localparam             IDLE = 8'h0;
        localparam      GET_COMMAND = 8'h1;
        localparam      GET_ADDRESS = 8'h2;
        localparam             READ = 8'h3;
        reg [7:0] state = 8'b0;
        reg [7:0] command = 8'b1;
        reg [23:0] address = 8'b1;
        reg [8:0] memory_byte = 9'b1;
        always @(posedge clock) begin
            case (state)
                GET_COMMAND: begin
                    command <= {command[6:0], data_in};
                    if (command[7]) begin
                        state <= IDLE;
                        case ({command[6:0], data_in})
                            `FLASH_READ: begin
                                address <= 24'b1;
                                state <= GET_ADDRESS;
                            end
                        endcase
                    end
                end
                GET_ADDRESS: begin
                    address <= {address[22:0], data_in};
                    if (address[23]) begin
                        memory_byte <= {memory[{address[22:0], data_in}], 1'b1};
                        state <= READ;
                    end
                end
            endcase
        end
        always @(negedge clock) begin
            case (state)
                READ: begin
                    data_out <= memory_byte[8];
                    memory_byte <= {memory_byte[7:0], 1'b0};
                    if (memory_byte[7:0] == 8'h80) begin
                        memory_byte <= {memory[address + 1'b1], 1'b1};
                        address <= address + 1'b1;
                    end
                end
            endcase
        end
        always @(posedge select) begin
            state <= IDLE;
        end
        always @(negedge select) begin
            command <= 8'b1;
            state <= GET_COMMAND;
        end
    endmodule
`endif
