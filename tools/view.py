#!/usr/bin/python3
import sys
if len(sys.argv) != 2:
    print(
"""usage: {0} <vram>
example: {0} /tmp/vram_0.txt
""")
    exit()
with open(sys.argv[1]) as file:
    x = 0
    for line in file:
        if line[0:2] == "//":
            continue
        if x % 8 == 0:
            print()
        print(bin(int(line[:-1], 16))[2:].zfill(16).replace('0', '.'), end='')
        x += 1
print()


