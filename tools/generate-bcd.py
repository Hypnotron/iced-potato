#!/usr/bin/python3
for i in range(16):
    print(".INIT_" + hex(i)[2].upper() + "(256'h", end='')
    for j in range(15, -1, -1):
        num = i * 16 + j
        print('0' + str(num // 100) + str(num // 10 % 10) + str(num % 10), end='')
    print("),")


