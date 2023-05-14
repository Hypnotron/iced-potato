#!/bin/bash
echo "//Generated by $0 $@"
line_count=0
bram_cell=0
header() {
    echo -n "SB_RAM40_4K #("
}
footer() {
    echo "
        .WRITE_MODE(32'b0), //0: 256x16
        .READ_MODE(32'b0)) bram${bram_cell} (
        .RDATA(raw_data[${bram_cell}]),
        .WDATA(16'b0),
        .RADDR({3'b0, address[8:1]}),
        .WADDR(11'b0),
        .MASK(16'b0),
        .RCLKE(start && 3'd${bram_cell} == address[11:9]),
        .RCLK(clock),
        .RE(start && 3'd${bram_cell} == address[11:9]),
        .WCLKE(1'b0),
        .WCLK(1'b0),
        .WE(1'b0));"
}
header
while read line; do
    if [ $line_count -eq 16 ]; then
        header
        line_count=0
        bram_cell=$(($bram_cell + 1))
    fi
    echo -ne "\n        .INIT_$(printf "%X" $line_count)(256'h$(tr ' ' '\n' <<< "${line}" | tac | tr '\n' ' ' | tr -d ' ')),"
    line_count=$(($line_count + 1))
    if [ $line_count -eq 16 ]; then
        footer
    fi
done < <(hexdump -ve '32/1 "%02x " 1/0 "\n"' "$1")
if [ $line_count -ne 16 ]; then
    footer
fi
echo "//End generated by $0 $@"
