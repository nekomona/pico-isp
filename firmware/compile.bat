riscv-none-embed-gcc -march=rv32i -Wl,-Bstatic,-T,sections.lds,--strip-debug -ffreestanding -nostdlib -o firmware.elf isp_boot.S fw_start.S main.c

riscv-none-embed-objcopy -O verilog firmware.elf fw.out
