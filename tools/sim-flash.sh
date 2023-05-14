#!/bin/bash
if [ "$#" -ne 2 ]; then
    echo "usage: $0 <bitstream> <filesystem>"
    echo "example: $0 main.bin fs.bin"
    exit 1
fi
blank_size_bitstream=$((1048576 - $(du -b "$1" | cut -f 1)))
blank_size_user=$((3145728 - $(du -b "$2" | cut -f 1)))
cat "$1" <(dd if=/dev/zero of=/dev/stdout bs=1 count="${blank_size_bitstream}") "$2" <(dd if=/dev/zero of=/dev/stdout bs=1 count="${blank_size_user}") | hexdump -ve '1/1 "%02X\n"' > /tmp/flash.txt
