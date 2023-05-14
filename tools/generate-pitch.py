#!/usr/bin/python3
for i in range(16):
    print(".INIT_" + hex(i)[2].upper() + "(256'h", end='')
    for j in range(15, -1, -1):
        num = i * 16 + j
        print(hex(int(4000 * 2 ** ((num - 64) / 48)))[2:].zfill(4), end='')
    print("),")


