# Make sure you are in the 'your_project/' directory
# Assuming the bootloader assembly is in 'bootloader/bootloader.asm'
# And the new kernel assembly is in 'kernel/aushkos_kernel.asm'

# 1. Assemble your custom kernel (AushkOS)
nasm -f bin kernel/aushkos_kernel.asm -o kernel/KERNEL.BIN

# 2. Assemble the bootloader (no changes needed for the bootloader itself)
nasm -f bin bootloader/bootloader.asm -o image/bootloader.bin

# 3. Create the floppy disk image file (ensure correct size 2880 for 1.44MB floppy)
dd if=/dev/zero of=image/myos.flp bs=512 count=2880

# 4. Format the floppy image with FAT12 filesystem
mkfs.fat -F 12 image/myos.flp

# 5. Install the bootloader onto the floppy image
dd if=image/bootloader.bin of=image/myos.flp bs=512 count=1 conv=notrunc

# 6. Copy your kernel to the floppy image
mcopy -i image/myos.flp kernel/KERNEL.BIN ::KERNEL.BIN

# 7. Boot the OS with QEMU
qemu-system-i386 -drive format=raw,file=image/myos.flp -nographic

