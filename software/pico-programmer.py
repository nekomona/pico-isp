
# coding: utf-8

# compile and linking
# to be optimized
# $ riscv32-unknown-elf-gcc -march=RV32IMC -Wl,-Bstatic,-T,sections.lds,--strip-debug -ffreestanding -nostdlib -o firmware.elf start.s isp_flasher.s firmware.c
# 
# $ riscv32-unknown-elf-objcopy.exe -O verilog firmware.elf firmware.out     

import serial, sys
import time

if len(sys.argv) != 3 or '-h' in sys.argv:
    print("Usage:")
    print("    Generate .coe file for bootloader:")
    print("      python pico-programmer.py <firmware.out file path> -c")
    print("    Download to ROM:")
    print("      python pico-programmer.py <firmware.out file path> <serial port>")
    sys.exit()

# Constants
brom_size = 4096

# read file
filepath = sys.argv[1]
file = open(filepath, 'r', buffering=8192)

# Bootloader section
lbootloader = []
blinecount = 0
# Program section
lprogram = []
plinecount = 0

# Split file into bootloader section and program section
lbegin = False
for line in file:
    if lbegin:
        lprogram.append(line)
        plinecount += 1
    elif line.startswith('@01000000'):
        lbegin = True
        lprogram.append(line)
    else:
        lbootloader.append(line)
        blinecount += 1

file.close()

if sys.argv[2] == '-c':
    # Generate coe file
    print("Building coe file")
    
    # Parse .out file into BROM data
    brom = [0] * brom_size
    wp = 0
    
    for i, lstr in enumerate(lbootloader):
        if lstr.startswith('@'):
            wp = int(lstr[1:], 16)
        for j, bprog in enumerate(lstr.split(' ')[0:-1]):
            brom[wp] = int(bprog, 16)
            wp += 1
    
    fp = open("bootloader.coe", "w+")
    
    fp.write("memory_initialization_radix=16;\n")
    fp.write("memory_initialization_vector=\n")
    
    first_line = True
    for i in range(0, brom_size, 4):
        pnum = (brom[i+3] << 24) | (brom[i+2] << 16) | (brom[i+1] << 8) | (brom[i])
        if first_line:
            first_line = False
        else:
            fp.write(",\n")
        fp.write("{:08x}".format(pnum))
    fp.write(";\n")
    fp.close()
    
else:
    # Do serial ISP program
    
    # Calculate program size
    nproglen = 16 * (plinecount-1) + len(lprogram[plinecount-1].split(' ')) - 1
    print("Read program with", nproglen, "bytes")

    prog = [0] * nproglen
    wp = 0
    flash_base = 0x01000000

    for i, lstr in enumerate(lprogram):
        if lstr.startswith('@'):
            wp = int(lstr[1:], 16) - flash_base
        for j, bprog in enumerate(lstr.split(' ')[0:-1]):
            prog[wp] = int(bprog, 16)
            wp += 1


    # open serial and check status
    ser = serial.Serial(sys.argv[2], 115200, timeout=0.1)
    ser.setDTR(True)
    time.sleep(0.01)
    ser.setDTR(False)
    
    print("  - Waiting for reset -", flush=True)
    print('    ', end='', flush=True)

    
    for i in range(100):
        ser.reset_input_buffer()
        ser.write(bytes([0x55, 0x55]))
        ser.flush()
        res = ser.read()
        
        time.sleep(0.1)

        if i % 10 == 0:
            print('.', end='', flush=True)
        
        if len(res) > 0 and res[0] == 0x56:
            break

    print("")

    if len(res) == 0 or res[0] != 0x56:
        print("Picorv32-tang not detected or not in isp mode")
        print("Check serial port or check reset button")
        ser.close()
        sys.exit()

    # begin programming

    pageind = 0
    wrtbyte = 0
    rembyte = len(prog)
    curraddr = 0
    pagestep = 256

    pagereq = ((rembyte - 1) // pagestep) + 1

    print("Total pages", pagereq)

    for i in range(pagereq):
        wlen = min(pagestep, rembyte - curraddr)
        wrbuf = [wlen-1]
        wrdat = prog[curraddr:curraddr+wlen]
        chksum = sum(wrdat) & 0xFF
        wrbuf = wrbuf + wrdat
        wrbyte = bytes(wrbuf)
        
        print(chksum)
        
        ser.write(bytes([0x10]))
        resp = []
        while len(resp) > 0 and resp[0] != 0x11:
            resp = ser.read()
            if len(resp) == 0:
                resp = bytes([0x00])
            elif resp[0] == 0x11:
                print("", end="")
                
        ser.write(wrbyte)
        resp = []
        while len(resp) > 0 and resp[0] != chksum:
            resp = ser.read()
            if len(resp) == 0:
                resp = bytes([0x00])
            elif resp[0] == chksum:
                print("", end="")
                # print("  Chksum get")
            else:
                print("  Bad chksum", resp[0])      

        pgbuf = bytes([(curraddr >> 16) & 0xFF, (curraddr >> 8) & 0xFF, curraddr & 0xFF])
        print(" Programming", j+i*16, "at", "0x01{:02x}{:02x}{:02x}".format(pgbuf[0], pgbuf[1], pgbuf[2]))
              
        ser.write(bytes([0x40]))
                  
        resp = bytes([0x00])
        while resp[0] != 0x41:
            resp = ser.read()
            if len(resp) == 0:
                resp = bytes([0x00])
            elif resp[0] == 0x41:
                print("", end="")
                # print("  Programming processing")
                  
        ser.write(pgbuf)

        resp = bytes([0x00]);
        while resp[0] != 0x42:
            resp = ser.read()
            if len(resp) == 0:
                resp = bytes([0x00])
            elif resp[0] == 0x42:
                print("", end="")
                #print("  Programming finished")
        
        curraddr += pagestep

    # reset system

    ser.write(bytes([0xF0]))
    ser.read()

    print("")
    print("Flashing completed")

    ser.close()

