#!/usr/bin/env python3
import sys
from PIL import Image

def main():
    if len(sys.argv) != 3:
        print("Usage: img2c.py [image] [output]")
        exit(-1)

    with open (sys.argv[2], "w") as output_f:
        img = Image.open(sys.argv[1])
        width, height = img.size

        output_f.write(f"const uint8_t ic_background[{width}*{height}*3] = ")
        output_f.write("{\n")
        for y in range(height):
            for x in range(width):
                coord = x, y
                r, g, b, a = img.getpixel(coord)

                if (r > 200): r = 255
                elif (r < 50): r = 0
                # else: r = 128
                if (g > 200): g = 255
                elif (g < 50): g = 0
                # else: g = 128
                if (b > 200): b = 255
                elif (b < 50): b = 0
                # else: b = 128
                output_f.write(hex(r))
                output_f.write(",")
                output_f.write(hex(g))
                output_f.write(",")
                output_f.write(hex(b))

                if not (y == (height - 1) and x == (width - 1)):
                    output_f.write(",")
            output_f.write("\n")
        output_f.write("};")

if __name__ == "__main__":
    main()
