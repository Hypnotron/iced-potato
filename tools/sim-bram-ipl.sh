#!/bin/bash
echo "WARNING: BRAM IPL is deprecated; you must hardcode metadata into top.v when using it."
if [ "$#" -ne 3 ]; then
    echo "usage: $0 <byte 0x1fe> <byte 0x1ff> <game>"
    echo "example: $0 0 0 game.ch8"
    exit 1
fi
blank_size=$((3584 - $(du -b "$3" | cut -f 1)))
echo $blank_size
cat font.bin <(dd if=/dev/zero of=/dev/stdout bs=1 count=430) <(printf "\x0${1}\x0${2}") "$3" <(dd if=/dev/zero of=/dev/stdout bs=1 count="${blank_size}") | hexdump -ve '1/2 "%04X\n"' > /tmp/bram_ipl.txt
for i in $(seq 0 7); do
    tail -n +$(($i * 256 + 1)) /tmp/bram_ipl.txt | head -n 256 > "/tmp/bram_ipl_${i}.txt"
done
