#!/usr/bin/python3
#TODO: detailed error messages
from sys import argv
from math import ceil

def write_bytes(destination, number, start, length):
    for i in range(start + length - 1, start - 1, -1):
        destination[i] = number & 0xFF
        number >>= 8

def write_string(destination, string, start, max_length):
    for i in range(0, min(len(string), max_length)):
        destination[start + i] = ord(string[i].upper())

def help():
    print(
"""usage: {0} (operation) (type) (options) <source> <destination>
examples:
    make game:      $ {0} make game font.bin conf.txt game.ch8 game.i8
    make fs:        $ {0} make fs game0.i8 game1.i8 ... fs.bin
    make font:      $ {0} make font <width> <horizontal spacing> <height> <vertical spacing> font.bmp font.bin
    make ascii_map: $ {0} make ascii_map map.txt map.bin
""".format(argv[0]))

def main():
    if  len(argv) >= 3 and argv[1] == "make":
        if  len(argv) >= 7 and argv[2] == "game":
            game = bytearray(512)
            file = open(argv[3], "rb")
            file.readinto(game)
            file.close()
            file = open(argv[4], "r")
            config = file.read()
            file.close()
            for line in config.split('\n'):
                try:
                    key, value = line.split('=')
                except:
                    continue
                key = key.strip(' ')
                if   key == "title":
                    write_string(game, value, 0x100, 0x20) 
                elif key == "author":
                    write_string(game, value, 0x120, 0x10)
                elif key == "description":
                    write_string(game, value, 0x130, 0x50)
                elif key == "quirks":
                    write_bytes(game, int(value, 0), 0x180, 0x8)
                elif key == "keymap":
                    write_bytes(game, int(value, 0), 0x188, 0x8)
                elif key == "palette":
                    write_bytes(game, int(value, 0), 0x190, 0x2)
                elif key == "instructions-per-frame":
                    write_bytes(game, int(value, 0), 0x192, 0x2)
                else:
                    continue
                print("writing {} to header".format(key))
            file = open(argv[5], "rb")
            game += file.read()
            file.close()
            write_bytes(game, ceil(len(game) / 256) - 1, 0x194, 0x1)
            print("writing last-page to header")
            file = open(argv[6], "wb")
            file.write(game)
            print("wrote output to {}".format(argv[6]))
            file.close()
        elif len(argv) >= 4 and argv[2] == "fs":
            game_index = 0
            game_page = 2
            filesystem = bytearray(512)
            for game in argv[3:-1]:
                print("adding {}".format(game))
                file = open(game, "rb")
                filesystem += file.read()
                filesystem += bytearray(-len(filesystem) % 256)
                write_bytes(filesystem, game_page, game_index * 2, 2)
                game_page = len(filesystem) >> 8
                game_index += 1
                file.close()
            file = open(argv[-1], "wb")
            file.write(filesystem)
            print("wrote output to {}".format(argv[-1]))
            file.close()
        elif len(argv) >= 7 and argv[2] == "font":
            import PIL.Image
            width = int(argv[3])
            if width > 8:
                print("error: width cannot exceed 8")
                exit()
            horizontal_spacing = int(argv[4])
            height = int(argv[5])
            vertical_spacing = int(argv[6])
            image = PIL.Image.open(argv[7])
            length = image.width // (width + horizontal_spacing) * image.height // height
            font = bytearray(0)
            x = 0
            y = 0
            for i in range(length):
                character = list(image.crop((x, y, x + width, y + height)).getdata())
                x += width + horizontal_spacing
                if x >= image.width:
                    x = 0
                    y += height + vertical_spacing
                for j in range(height):
                    byte = 0x00
                    for k in range(8):
                        byte <<= 1
                        if k < width:
                            byte |= character[j * width + k] == (0, 0, 0)
                    font.append(byte)
            image.close()
            file = open(argv[8], "wb")
            file.write(font)
            print("wrote output to {}".format(argv[8]))
            file.close()
        elif len(argv) >= 5 and argv[2] == "ascii_map":
            binary_map = bytearray(256)
            file = open(argv[3], "r")
            text_map = file.read()
            file.close()
            print("mapping {} characters".format(len(text_map)))
            for i in range(1, 256):
                binary_map[i] = text_map.find(chr(i)) & 0xFF
            file = open(argv[4], "wb")
            file.write(binary_map)
            print("wrote output to {}".format(argv[4]))
            file.close()
        else:
            help()
            exit()
    else:
        help()
        exit()
main()
