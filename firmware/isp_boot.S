.section .init
.global start

start:
# initialize stack
la sp, _stack_start

# loop and wait for isp command
li t0, 0x40000000  # load UART base
li t2, 0x55        # preload instruction byte
li t5, 10         # outer loop count

mL0:
# loop read
li t4, 80000       # inner loop count

mL1:
jal isp_xuart_read
beq a2, t2, mRun   # Goto ISP if instruction byte received
addi t4, t4, -1    # Inner loop
bnez t4, mL1

addi t5, t5, -1    # Outer loop
bnez t5, mL0

la t0, flstart     # No ISP command received, jump to the beginning of program
jalr t0

endloop:           # This section should not be reached, used as a guard
j endloop

mRun:
# go to flasher
la a0, _ram_start
j isp_flasher_begin

# address of UART base
# always saved in t0
# XUartLite @0x40000000
# 0x00h RX FIFO
# 0x04h TX FIFO
# 0x08h STAT_REG
# 0x0Ch CTRL_REG

# Read UART non-blocking
# result in a2
# non-negative: received byte valid
# negative:     no valid data
isp_xuart_read:
li a2, -1                     # Preset a non-valid value
lw t3, 0x08(t0)               # Read STAT_REG
andi t3, t3, 0x01             # Check RX FIFO valid bit
beqz t3, isp_xuart_read_nvld  # Check and skip reading if data is not valid 
lw a2, 0x00(t0)               # Read received data
isp_xuart_read_nvld:
ret

# Write UART blocking
# word to write in a2
isp_xuart_write:
isp_xuart_write_L0:
lw t3, 0x08(t0)               # Read STAT_REG
andi t3, t3, 0x08             # Check TX FIFO full bit
bnez t3, isp_xuart_write_L0   # Check and wait if TX FIFO full
sw a2, 0x04(t0)               # Write data
ret

isp_flasher_begin:
# a0 ... instr buffer pointer
#   0 instr
#   1-3 addr
#   4-259 page dat
# a1 ... flashio pointer

li t0, 0x40000000
li t6, 0

# instr read
isp_flasher_IREAD:
jal isp_xuart_read            # Read Instr byte
bltz a2, isp_flasher_IREAD    # Loop if instr not valid

# Check instruction
li t2, 0x55                   # Ack
beq a2, t2, isp_flasher_ACK
li t2, 0x10                   # Write data from UART to buffer
beq a2, t2, isp_flasher_WBUF
li t2, 0x40                   # Write buffer to 'program ROM'
beq a2, t2, isp_flasher_WPAG
li t2, 0xF0                   # Software reset
beq a2, t2, isp_flasher_RST

# Repeat ISP loop
j isp_flasher_IREAD

# Ack - Show ISP is ready
# receive  0x55
# transmit 0x56
isp_flasher_ACK:
li a2, 0x56
jal isp_xuart_write
j isp_flasher_IREAD

# Write buffer - Receive data into buffer
# receive  0x10 len dat0-datn
# transmit 0x11
# receive  (length-1) (1B), data (length B)
# transmit checksum
isp_flasher_WBUF:
li a2, 0x11                   # Send instruction acknoledge
jal isp_xuart_write

isp_flasher_RLEN:
jal isp_xuart_read            # Receive (length-1)
bltz a2, isp_flasher_RLEN
addi t1, a2, 1                # length = (length-1) + 1
addi t6, t1, 0                # store length to t6 for writing into ROM

addi t2, a0, 4                # Set t2 to write position
li t4, 0                      # Use t4 for checksum
isp_flasher_RDAT:
jal isp_xuart_read            # Loop to receive a valid byte
bltz a2, isp_flasher_RDAT
sb a2, 0(t2)                  # Store received byte to buffer
addi t2, t2, 1                # Add storage pointer
addi t1, t1, -1               # Reduce remain count
add t4, t4, t3                # Summing checksum
bnez t1, isp_flasher_RDAT

isp_flasher_RCOMP:
andi t4, t4, 0xFF             # Send checksum
mv a2, t4
jal isp_xuart_write

j isp_flasher_IREAD

# Page write - Write buffer data to ROM
# page length is acquired from last wbuf, stored in t6
# Receive  0x40
# Transmit 0x41
# Receive  Address[2], Address[1], Address[0]
# Transmit 0x42
isp_flasher_WPAG:
li a2, 0x41                   # Send ack
jal isp_xuart_write

li t1, 0x01

isp_flasher_WRADA:            # Repeat 3 times to read 24b address (first byte is fixed to 0x01)
jal isp_xuart_read
bltz a2, isp_flasher_WRADA
slli t1, t1, 8
add t1, t1, a2                # Address[2]

isp_flasher_WRADB:
jal isp_xuart_read
bltz a2, isp_flasher_WRADB
slli t1, t1, 8
add t1, t1, a2                # Address[1]

isp_flasher_WRADC:
jal isp_xuart_read
bltz a2, isp_flasher_WRADC
slli t1, t1, 8
add t1, t1, a2                # Address[0]

beqz t6, isp_flasher_WFIN     # Check to avoid length = 0

# Write data from buffer to ROM
# This section is replaced with FLASH unlock or SPI erase and write command in practical ISP
addi t2, a0, 4                # Set t2 to read position
                              # t1 is write postion
                              # Remain count in t6
isp_flasher_WDAT:
lb a2, 0(t2)                  # Fetch a byte from buffer
sb a2, 0(t1)                  # Store the byte to ROM
addi t2, t2, 1                # Add read and write pointers
addi t1, t1, 1
addi t6, t6, -1               # Reduce remain count
bnez t6, isp_flasher_WDAT

isp_flasher_WFIN:
li a2, 0x42                   # Reply finish
jal isp_xuart_write
j isp_flasher_IREAD

# reset system
# receive 0xF0
# transmit 0xF1
isp_flasher_RST:
li a2, 0xF1
jal isp_xuart_write
# Jump to entry point for a software reset
li t1, 0x00000000
jalr x0, t1, 0

isp_flasher_end:
