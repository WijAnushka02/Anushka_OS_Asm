; ==================================================================
; The Mike Operating System bootloader (Minimal Size for 512 bytes)
; Copyright (C) 2006 - 2022 MikeOS Developers -- see doc/LICENSE.TXT
;
; This version is strictly optimized to fit within 512 bytes.
; All non-critical/verbose messages are handled by the kernel.
; ==================================================================


    BITS 16

    jmp short bootloader_start  ; Jump past disk description section
    nop           ; Pad out before disk description


; ------------------------------------------------------------------
; Disk description table, to make it a valid floppy
; Note: some of these values are hard-coded in the source!
; Values are those used by IBM for 1.44 MB, 3.5" diskette

OEMLabel        db "MIKEBOOT"   ; Disk label
BytesPerSector  dw 512      ; Bytes per sector
SectorsPerCluster   db 1        ; Sectors per cluster
ReservedForBoot     dw 1        ; Reserved sectors for boot record
NumberOfFats        db 2        ; Number of copies of the FAT
RootDirEntries      dw 224      ; Number of entries in root dir
                    ; (224 * 32 = 7168 = 14 sectors to read)
LogicalSectors      dw 2880     ; Number of logical sectors
MediumByte      db 0F0h     ; Medium descriptor byte
SectorsPerFat       dw 9        ; Sectors per FAT
SectorsPerTrack     dw 18       ; Sectors per track (36/cylinder)
Sides           dw 2        ; Number of sides/heads
HiddenSectors       dd 0        ; Number of hidden sectors
LargeSectors        dd 0        ; Number of LBA sectors
DriveNo         dw 0        ; Drive No: 0
Signature       db 41       ; Drive signature: 41 for floppy
VolumeID        dd 00000000h    ; Volume ID: any number
VolumeLabel     db "MIKEOS    "; Volume Label: any 11 chars
FileSystem      db "FAT12   "   ; File system type: don't change!


; ------------------------------------------------------------------
; Main bootloader code

bootloader_start:
    ; Set up stack space.
    mov ax, 07C0h
    add ax, 544
    cli
    mov ss, ax
    mov sp, 4096
    sti

    mov ax, 07C0h
    mov ds, ax

    ; NOTE: A few early BIOSes are reported to improperly set DL.
    cmp dl, 0
    je no_change
    mov [bootdev], dl
    mov ah, 8
    int 13h
    jc fatal_disk_error
    and cx, 3Fh
    mov [SectorsPerTrack], cx
    movzx dx, dh
    add dx, 1
    mov [Sides], dx

no_change:
    mov eax, 0


floppy_ok:
    mov ax, 19
    call l2hts

    mov si, buffer
    mov bx, ds
    mov es, bx
    mov bx, si

    mov ah, 2
    mov al, 14

    pusha


read_root_dir:
    popa
    pusha

    stc
    int 13h

    jnc search_dir
    call reset_floppy
    jnc read_root_dir

    ; Error message if boot disk read fails (critical)
    mov si, boot_fail_msg
    call print_string
    jmp reboot


search_dir:
    popa

    mov ax, ds
    mov es, ax
    mov di, buffer

    mov cx, word [RootDirEntries]
    mov ax, 0


next_root_entry:
    xchg cx, dx

    mov si, kern_filename
    mov cx, 11
    rep cmpsb
    je found_file_to_load

    add ax, 32

    mov di, buffer
    add di, ax

    xchg dx, cx
    loop next_root_entry

    ; Error message if KERNEL.BIN is not found (critical)
    mov si, kernel_not_found_msg
    call print_string
    jmp reboot


found_file_to_load:
    mov ax, word [es:di+0Fh]
    mov word [cluster], ax

    mov ax, 1
    call l2hts

    mov di, buffer
    mov bx, di

    mov ah, 2
    mov al, 9

    pusha


read_fat:
    popa
    pusha

    stc
    int 13h

    jnc read_fat_ok
    call reset_floppy
    jnc read_fat

fatal_disk_error:
    ; General floppy error message (critical)
    mov si, disk_err_msg
    call print_string
    jmp reboot


read_fat_ok:
    popa

    mov ax, 2000h
    mov es, ax
    mov bx, 0

    mov ah, 2
    mov al, 1

    push ax


load_file_sector:
    mov ax, word [cluster]
    add ax, 31

    call l2hts

    mov bx, word [pointer]

    pop ax
    push ax

    stc
    int 13h

    jnc calculate_next_cluster

    call reset_floppy
    jmp load_file_sector


calculate_next_cluster:
    mov ax, [cluster]
    mov dx, 0
    mov bx, 3
    mul bx
    mov bx, 2
    div bx
    mov si, buffer
    add si, ax
    mov ax, word [ds:si]

    or dx, dx

    jz even
odd:
    shr ax, 4
    jmp short next_cluster_cont
even:
    and ax, 0FFFh


next_cluster_cont:
    mov word [cluster], ax

    cmp ax, 0FF8h
    jae end

    add word [pointer], 512
    jmp load_file_sector


end:
    pop ax
    mov dl, byte [bootdev]

    jmp 2000h:0000h


; ------------------------------------------------------------------
; BOOTLOADER SUBROUTINES (optimized for minimal size)

reboot:
    mov ax, 0
    int 16h
    mov ax, 0
    int 19h


print_string: ; This is kept as-is, essential for printing errors
    pusha
    mov ah, 0Eh
.repeat:
    lodsb
    cmp al, 0
    je .done
    int 10h
    jmp short .repeat
.done:
    popa
    ret

; Removed print_newline from bootloader to save space.
; Error messages will now print on the same line if newline isn't explicitly inserted (e.g. by CR/LF in string).
; For critical errors, short single-line messages are common anyway.

reset_floppy:
    push ax
    push dx
    mov ax, 0
    mov dl, byte [bootdev]
    stc
    int 13h
    pop dx
    pop ax
    ret


l2hts:
    push bx
    push ax

    mov bx, ax

    mov dx, 0
    div word [SectorsPerTrack]
    add dl, 01h
    mov cl, dl
    mov ax, bx

    mov dx, 0
    div word [SectorsPerTrack]
    mov dx, 0
    div word [Sides]
    mov dh, dl
    mov ch, al

    pop ax
    pop bx

    mov dl, byte [bootdev]

    ret


; ------------------------------------------------------------------
; STRINGS AND VARIABLES (kept minimal for boot sector)

    kern_filename       db "KERNEL  BIN"

    ; Critical, SHORT error messages that MUST stay in bootloader
    boot_fail_msg       db "BOOT FAIL!", 13, 10, 0 ; Added CR/LF directly for minimal newline
    kernel_not_found_msg db "KRNL NOT FND!", 13, 10, 0
    disk_err_msg        db "DISK ERR!", 13, 10, 0

    bootdev         db 0
    cluster         dw 0
    pointer         dw 0


; ------------------------------------------------------------------
; END OF BOOT SECTOR AND BUFFER START

    times 510-($-$$) db 0   ; Pad remainder of boot sector with zeros
    dw 0AA55h               ; Boot signature (DO NOT CHANGE!)


buffer:
