#!/bin/bash
echo "WARNING: loading games directly into memory is deprecated; use BRAM IPL or flash instead."
if [ "$#" -ne 3]; then
    echo "usage: $0 <byte 0x1fe> <byte 0x1ff> <game>"
    echo "example: $0 0 0 game.ch8"
    exit 1
fi
blank_size=$((65024 - $(du -b "$3" | cut -f 1)))
echo $blank_size
cat font.bin <(dd if=/dev/zero of=/dev/stdout bs=1 count=430) <(printf "\x0${1}\x0${2}") "$3" <(dd if=/dev/zero of=/dev/stdout bs=1 count="${blank_size}") | hexdump -ve '1/2 "%04X\n"' > /tmp/cpu_mm.txt
head -n 16384 /tmp/cpu_mm.txt > /tmp/cpu_mm_0.txt
tail -n 16384 /tmp/cpu_mm.txt > /tmp/cpu_mm_1.txt
